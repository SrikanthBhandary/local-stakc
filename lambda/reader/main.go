package main

import (
	"context"
	"encoding/json"
	"log"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
)

type Enquiry struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	Email     string  `json:"email"`
	Phone     string  `json:"phone"`
	Travelers int     `json:"travelers"`
	Tour      string  `json:"tour"`
	Dates     string  `json:"dates"`
	Message   string  `json:"message"`
	Lat       float64 `json:"lat,omitempty"`
	Lng       float64 `json:"lng,omitempty"`
	Geohash   string  `json:"geohash,omitempty"`
	Status    string  `json:"status"`
	CreatedAt string  `json:"createdAt"`
	EmailSent bool    `json:"emailSent"`
}

func jsonResponse(
	status int,
	body interface{},
) (events.APIGatewayProxyResponse, error) {

	data, err := json.Marshal(body)

	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Body:       `{"error":"json marshal failed"}`,
		}, nil
	}

	return events.APIGatewayProxyResponse{

		StatusCode: status,

		Headers: map[string]string{
			"Content-Type":                "application/json",
			"Access-Control-Allow-Origin": "*",
		},

		Body: string(data),
	}, nil
}

func handler(
	ctx context.Context,
	req events.APIGatewayProxyRequest,
) (events.APIGatewayProxyResponse, error) {

	table := os.Getenv("TABLE")

	cfg, err := config.LoadDefaultConfig(ctx)

	if err != nil {

		log.Println("AWS config error:", err)

		return jsonResponse(
			500,
			map[string]string{
				"error": "aws config failed",
			},
		)
	}

	// MiniStack / LocalStack support
	endpoint := os.Getenv("AWS_ENDPOINT_URL")

	var dynamoOptions []func(*dynamodb.Options)

	if endpoint != "" {

		dynamoOptions = append(
			dynamoOptions,
			func(o *dynamodb.Options) {

				o.BaseEndpoint =
					aws.String(endpoint)

			},
		)
	}

	db := dynamodb.NewFromConfig(
		cfg,
		dynamoOptions...,
	)

	// Optional: see who called the API
	// Cognito claims are injected by API Gateway
	if req.RequestContext.Authorizer != nil {

		log.Printf(
			"authorizer: %+v",
			req.RequestContext.Authorizer,
		)

	}

	result, err := db.Scan(
		ctx,
		&dynamodb.ScanInput{

			TableName: aws.String(table),
		},
	)

	if err != nil {

		log.Println(
			"DynamoDB scan failed:",
			err,
		)

		return jsonResponse(
			500,
			map[string]string{
				"error": "database error",
			},
		)

	}

	var enquiries []Enquiry

	err = attributevalue.UnmarshalListOfMaps(
		result.Items,
		&enquiries,
	)

	if err != nil {

		log.Println(
			"Unmarshal failed:",
			err,
		)

		return jsonResponse(
			500,
			map[string]string{
				"error": "decode failed",
			},
		)

	}

	return jsonResponse(
		200,
		map[string]interface{}{

			"count": len(enquiries),

			"items": enquiries,
		},
	)

}

func main() {

	lambda.Start(handler)

}
