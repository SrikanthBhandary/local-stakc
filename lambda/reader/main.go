package reader

import (
	"context"
	"encoding/json"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

type Item struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Price     int    `json:"price"`
	Processed bool   `json:"processed"`
}

func handler(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {

	cfg, _ := config.LoadDefaultConfig(ctx)

	db := dynamodb.NewFromConfig(cfg)

	table := os.Getenv("TABLE")

	out, _ := db.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(table),
		Key: map[string]types.AttributeValue{
			"id": &types.AttributeValueMemberS{
				Value: req.PathParameters["id"],
			},
		},
	})

	var item Item

	attributevalue.UnmarshalMap(out.Item, &item)

	data, _ := json.Marshal(item)

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(data),
	}, nil
}

func main() {
	lambda.Start(handler)
}
