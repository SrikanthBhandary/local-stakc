package main

import (
	"context"
	"encoding/json"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

func handler(ctx context.Context, event events.SQSEvent) error {

	cfg, _ := config.LoadDefaultConfig(ctx)

	db := dynamodb.NewFromConfig(cfg)

	table := os.Getenv("TABLE")

	for _, record := range event.Records {

		var msg map[string]interface{}

		json.Unmarshal([]byte(record.Body), &msg)

		id := strings.TrimSuffix(msg["Records"].([]interface{})[0].(map[string]interface{})["s3"].(map[string]interface{})["object"].(map[string]interface{})["key"].(string), ".json")

		db.UpdateItem(ctx, &dynamodb.UpdateItemInput{
			TableName: aws.String(table),
			Key: map[string]types.AttributeValue{
				"id": &types.AttributeValueMemberS{
					Value: id,
				},
			},
			UpdateExpression: aws.String("SET processed = :p"),
			ExpressionAttributeValues: map[string]types.AttributeValue{
				":p": &types.AttributeValueMemberBOOL{
					Value: true,
				},
			},
		})
	}

	return nil
}

func main() {
	lambda.Start(handler)
}
