package main

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/mail"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/ses"
	sestypes "github.com/aws/aws-sdk-go-v2/service/ses/types"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

const geohashPrecision = 6 // ~0.6km cells; adjust for coarser/finer proximity buckets

// EnquiryInput is what the frontend form sends.
type EnquiryInput struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	Email     string  `json:"email"`
	Phone     string  `json:"phone"`
	Travelers int     `json:"travelers"`
	Tour      string  `json:"tour"`
	Dates     string  `json:"dates"`
	Message   string  `json:"message"`
	Lat       float64 `json:"lat"`
	Lng       float64 `json:"lng"`
}

// EnquiryRecord is what gets stored in DynamoDB.
type EnquiryRecord struct {
	ID        string  `dynamodbav:"id"`
	Name      string  `dynamodbav:"name"`
	Email     string  `dynamodbav:"email"`
	Phone     string  `dynamodbav:"phone"`
	Travelers int     `dynamodbav:"travelers"`
	Tour      string  `dynamodbav:"tour"`
	Dates     string  `dynamodbav:"dates"`
	Message   string  `dynamodbav:"message"`
	Lat       float64 `dynamodbav:"lat,omitempty"`
	Lng       float64 `dynamodbav:"lng,omitempty"`
	Geohash   string  `dynamodbav:"geohash,omitempty"`
	Status    string  `dynamodbav:"status"`
	CreatedAt string  `dynamodbav:"createdAt"`
	EmailSent bool    `dynamodbav:"emailSent"`
}

func jsonResponse(status int, body interface{}, extraHeaders map[string]string) events.APIGatewayProxyResponse {
	data, _ := json.Marshal(body)
	headers := map[string]string{"Content-Type": "application/json"}
	for k, v := range extraHeaders {
		headers[k] = v
	}
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers:    headers,
		Body:       string(data),
	}
}

func newID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		// Extremely unlikely; fall back to a timestamp-based id rather than fail the request.
		return fmt.Sprintf("enq-%d", time.Now().UnixNano())
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func validate(in EnquiryInput) error {
	if strings.TrimSpace(in.Name) == "" {
		return fmt.Errorf("name is required")
	}
	if strings.TrimSpace(in.Email) == "" {
		return fmt.Errorf("email is required")
	}
	if _, err := mail.ParseAddress(in.Email); err != nil {
		return fmt.Errorf("email is not valid")
	}
	if strings.TrimSpace(in.Phone) == "" {
		return fmt.Errorf("phone is required")
	}
	if strings.TrimSpace(in.Tour) == "" {
		return fmt.Errorf("tour is required")
	}
	if strings.TrimSpace(in.Dates) == "" {
		return fmt.Errorf("dates is required")
	}
	if in.Lat != 0 && (in.Lat < -90 || in.Lat > 90) {
		return fmt.Errorf("lat out of range")
	}
	if in.Lng != 0 && (in.Lng < -180 || in.Lng > 180) {
		return fmt.Errorf("lng out of range")
	}
	return nil
}

func sendConfirmationEmail(ctx context.Context, sesClient *ses.Client, fromAddr string, rec EnquiryRecord) error {
	subject := fmt.Sprintf("We've received your enquiry — %s", rec.Tour)
	body := fmt.Sprintf(
		"Hi %s,\n\nThanks for your enquiry about %s.\n\nPreferred dates: %s\nTravelers: %d\n\nOur travel desk will follow up within 24 hours with availability, hotel options, and pricing.\n\n— High Passes",
		rec.Name, rec.Tour, rec.Dates, rec.Travelers,
	)

	_, err := sesClient.SendEmail(ctx, &ses.SendEmailInput{
		Source: aws.String(fromAddr),
		Destination: &sestypes.Destination{
			ToAddresses: []string{rec.Email},
		},
		Message: &sestypes.Message{
			Subject: &sestypes.Content{Data: aws.String(subject)},
			Body: &sestypes.Body{
				Text: &sestypes.Content{Data: aws.String(body)},
			},
		},
	})
	return err
}

func handler(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	table := os.Getenv("TABLE")
	rateLimitTable := os.Getenv("RATE_LIMIT_TABLE")
	fromAddr := os.Getenv("SES_FROM_ADDRESS")

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Printf("LoadDefaultConfig failed: %v", err)
		return jsonResponse(500, map[string]string{"error": "internal error"}, nil), nil
	}

	// Don't rely on the SDK auto-discovering a local endpoint — explicitly
	// point at it if AWS_ENDPOINT_URL is set. Without this, the SDK happily
	// resolves to real AWS and fails with UnrecognizedClientException using
	// MiniStack/LocalStack's dummy "test" credentials.
	endpointOverride := os.Getenv("AWS_ENDPOINT_URL")

	var dynamoOpts []func(*dynamodb.Options)
	var sesOpts []func(*ses.Options)
	if endpointOverride != "" {
		dynamoOpts = append(dynamoOpts, func(o *dynamodb.Options) { o.BaseEndpoint = aws.String(endpointOverride) })
		sesOpts = append(sesOpts, func(o *ses.Options) { o.BaseEndpoint = aws.String(endpointOverride) })
	}

	db := dynamodb.NewFromConfig(cfg, dynamoOpts...)
	sesClient := ses.NewFromConfig(cfg, sesOpts...)

	// --- throttling: reject early, before touching the enquiries table ---
	sourceIP := req.RequestContext.Identity.SourceIP
	allowed, retryAfter, err := checkRateLimit(ctx, db, rateLimitTable, sourceIP)
	log.Printf("rate limit check: sourceIP=%q table=%q allowed=%v retryAfter=%d err=%v",
		sourceIP, rateLimitTable, allowed, retryAfter, err)

	if err != nil {
		log.Printf("rate limit check failed, failing OPEN: %v", err)
		// Fail open on infra errors — a broken rate limiter shouldn't block
		// real customers. If you're seeing requests never get throttled,
		// check the log line above first: sourceIP="" means this request
		// never went through API Gateway's proxy integration (e.g. a direct
		// Lambda invoke, or the wrong event type for a Function URL), so
		// there's no per-caller identity to rate-limit on.
	} else if !allowed {
		log.Printf("rate limit exceeded for %s", sourceIP)
		return jsonResponse(429,
			map[string]string{"error": "Too many requests. Please try again shortly."},
			map[string]string{"Retry-After": strconv.Itoa(retryAfter)},
		), nil
	}

	// --- parse & validate ---
	var input EnquiryInput
	if err := json.Unmarshal([]byte(req.Body), &input); err != nil {
		return jsonResponse(400, map[string]string{"error": "invalid JSON body"}, nil), nil
	}
	if err := validate(input); err != nil {
		return jsonResponse(400, map[string]string{"error": err.Error()}, nil), nil
	}

	isDup, dupErr := checkDuplicateSubmission(ctx, db, rateLimitTable, input.Email, input.Tour)
	if dupErr != nil {
		log.Printf("duplicate check failed: %v", dupErr)
		// Fail open — an infra hiccup here shouldn't block a genuine enquiry.
	} else if isDup {
		log.Printf("duplicate submission for email=%s tour=%s within cooldown window", input.Email, input.Tour)
		return jsonResponse(200, map[string]string{
			"status":  "already_received",
			"message": "We've already got an enquiry from you for this route and will be in touch shortly.",
		}, nil), nil
	}

	id := input.ID
	if strings.TrimSpace(id) == "" {
		id = newID()
	}

	record := EnquiryRecord{
		ID:        id,
		Name:      input.Name,
		Email:     input.Email,
		Phone:     input.Phone,
		Travelers: input.Travelers,
		Tour:      input.Tour,
		Dates:     input.Dates,
		Message:   input.Message,
		Lat:       input.Lat,
		Lng:       input.Lng,
		Status:    "pending",
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
		EmailSent: false,
	}
	if input.Lat != 0 && input.Lng != 0 {
		record.Geohash = geohashEncode(input.Lat, input.Lng, geohashPrecision)
	}

	av, err := attributevalue.MarshalMap(record)
	if err != nil {
		log.Printf("MarshalMap failed: %v", err)
		return jsonResponse(500, map[string]string{"error": "internal error"}, nil), nil
	}

	// ConditionExpression makes a resubmitted/duplicate id a no-op success
	// instead of an overwrite or an error — handles double-clicks and client retries.
	_, err = db.PutItem(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(table),
		Item:                av,
		ConditionExpression: aws.String("attribute_not_exists(id)"),
	})
	if err != nil {
		var condFailed *types.ConditionalCheckFailedException
		if ok := errors.As(err, &condFailed); ok {
			log.Printf("duplicate enquiry id %s, treating as already recorded", id)
			return jsonResponse(200, map[string]string{"id": id, "status": "pending"}, nil), nil
		}
		log.Printf("PutItem failed: %v", err)
		return jsonResponse(500, map[string]string{"error": "could not save enquiry"}, nil), nil
	}

	// --- confirmation email: best effort, never fails the request ---
	if fromAddr == "" {
		log.Printf("SES_FROM_ADDRESS not configured, skipping confirmation email")
	} else if err := sendConfirmationEmail(ctx, sesClient, fromAddr, record); err != nil {
		log.Printf("sendConfirmationEmail failed for enquiry %s: %v", id, err)
	} else {
		_, uerr := db.UpdateItem(ctx, &dynamodb.UpdateItemInput{
			TableName: aws.String(table),
			Key: map[string]types.AttributeValue{
				"id": &types.AttributeValueMemberS{Value: id},
			},
			UpdateExpression: aws.String("SET emailSent = :t"),
			ExpressionAttributeValues: map[string]types.AttributeValue{
				":t": &types.AttributeValueMemberBOOL{Value: true},
			},
		})
		if uerr != nil {
			log.Printf("failed to mark emailSent for %s: %v", id, uerr)
		}
	}
	// TODO: Dirtyway to handle everything in one place.
	// Lets enqueue the dynambo table id in the sqs
	// and processor lambda will handle the creation of the pdf
	var sqsOpts []func(*sqs.Options)

	if endpointOverride != "" {
		sqsOpts = append(sqsOpts, func(o *sqs.Options) {
			o.BaseEndpoint = aws.String(endpointOverride)
		})
	}

	sqsClient := sqs.NewFromConfig(cfg, sqsOpts...)
	queueURL := os.Getenv("QUEUE_URL")

	payload := map[string]string{
		"id": id,
	}

	body, _ := json.Marshal(payload)

	_, err = sqsClient.SendMessage(ctx, &sqs.SendMessageInput{
		QueueUrl:    aws.String(queueURL),
		MessageBody: aws.String(string(body)),
	})

	if err != nil {
		log.Printf("failed to enqueue job: %v", err)
	}

	return jsonResponse(200, map[string]string{"id": id, "status": "pending"}, nil), nil
}

func main() {
	log.SetOutput(os.Stdout)
	lambda.Start(handler)
}
