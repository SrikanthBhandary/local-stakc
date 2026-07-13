package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type Item struct {
	ID        string `json:"id" dynamodbav:"id"`
	Name      string `json:"name" dynamodbav:"name"`
	Price     int    `json:"price" dynamodbav:"price"`
	Processed bool   `json:"processed" dynamodbav:"processed"`
}

func handler(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {

	log.Printf("Incoming request body: %s", req.Body)

	table := os.Getenv("TABLE")
	bucket := os.Getenv("BUCKET")

	log.Printf("TABLE=%s", table)
	log.Printf("BUCKET=%s", bucket)

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Printf("LoadDefaultConfig failed: %v", err)
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Body:       err.Error(),
		}, err
	}

	var item Item

	if err := json.Unmarshal([]byte(req.Body), &item); err != nil {
		log.Printf("Unmarshal failed: %v", err)
		return events.APIGatewayProxyResponse{
			StatusCode: 400,
			Body:       err.Error(),
		}, err
	}

	item.Processed = false

	log.Printf("Parsed Item: %+v", item)

	db := dynamodb.NewFromConfig(cfg)

	av, err := attributevalue.MarshalMap(item)
	if err != nil {
		log.Printf("MarshalMap failed: %v", err)
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Body:       err.Error(),
		}, err
	}

	_, err = db.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(table),
		Item:      av,
	})

	if err != nil {
		log.Printf("PutItem failed: %v", err)
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Body:       err.Error(),
		}, err
	}

	log.Printf("Successfully inserted item into DynamoDB")

	s3Client := s3.NewFromConfig(cfg)

	_, err = s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(item.ID + ".json"),
		Body:   strings.NewReader(req.Body),
	})

	if err != nil {
		log.Printf("PutObject failed: %v", err)
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Body:       err.Error(),
		}, err
	}

	log.Printf("Successfully uploaded object to S3")

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       "saved",
	}, nil
}

func main() {
	lambda.Start(handler)
}
