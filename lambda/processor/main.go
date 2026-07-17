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

	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

type Job struct {
	ID string `json:"id"`
}

func handler(ctx context.Context, event events.SQSEvent) error {

	log.Printf("Processor invoked with %d message(s)", len(event.Records))

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Printf("failed loading AWS config: %v", err)
		return err
	}

	// MiniStack / LocalStack support
	endpoint := os.Getenv("AWS_ENDPOINT_URL")

	var dynamoOptions []func(*dynamodb.Options)

	if endpoint != "" {
		log.Printf("Using DynamoDB endpoint %s", endpoint)

		dynamoOptions = append(
			dynamoOptions,
			func(o *dynamodb.Options) {
				o.BaseEndpoint = aws.String(endpoint)
			},
		)
	}

	db := dynamodb.NewFromConfig(cfg, dynamoOptions...)

	table := os.Getenv("TABLE")

	if table == "" {
		log.Println("TABLE environment variable not configured")
		return nil
	}

	for _, message := range event.Records {

		log.Printf("Received SQS message: %s", message.Body)

		var job Job

		if err := json.Unmarshal([]byte(message.Body), &job); err != nil {
			log.Printf("invalid message: %v", err)
			continue
		}

		if job.ID == "" {
			log.Printf("message missing enquiry id")
			continue
		}

		log.Printf("Processing enquiry %s", job.ID)

		_, err := db.UpdateItem(ctx, &dynamodb.UpdateItemInput{
			TableName: aws.String(table),

			Key: map[string]types.AttributeValue{
				"id": &types.AttributeValueMemberS{
					Value: job.ID,
				},
			},

			UpdateExpression: aws.String("SET #p = :p"),

			ExpressionAttributeNames: map[string]string{
				"#p": "processed",
			},

			ExpressionAttributeValues: map[string]types.AttributeValue{
				":p": &types.AttributeValueMemberBOOL{
					Value: true,
				},
			},
		})

		if err != nil {
			log.Printf("failed updating enquiry %s: %v", job.ID, err)
			continue
		}

		log.Printf("Successfully processed enquiry %s", job.ID)
	}

	log.Println("Processor completed successfully")

	return nil
}

func main() {
	log.SetOutput(os.Stdout)
	lambda.Start(handler)
}
