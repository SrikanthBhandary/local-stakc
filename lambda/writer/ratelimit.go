package main

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

const (
	rateLimitWindowSeconds = 60
	rateLimitMaxRequests   = 5
)

// checkRateLimit enforces "at most rateLimitMaxRequests per
// rateLimitWindowSeconds, per source IP".
//
// This does an explicit GetItem-then-check BEFORE attempting the increment,
// rather than relying solely on the UpdateItem's ConditionExpression to
// reject over-limit callers. Reason: some DynamoDB-compatible emulators
// (observed with MiniStack) accept a ConditionExpression on UpdateItem
// without actually evaluating it — the call just succeeds every time,
// silently disabling the limiter. The GetItem check here is what actually
// enforces the limit in that case.
//
// The ConditionExpression is still kept on the UpdateItem call below: on
// real DynamoDB (which does enforce it), that makes the whole
// check-and-increment atomic and closes the race window between the
// GetItem and the UpdateItem. On a store that ignores conditions, that gap
// does reopen — two concurrent requests could both pass the GetItem check
// right at the boundary and both get through. Acceptable trade-off for
// abuse protection; not meant to be a precise distributed counter.
func checkRateLimit(ctx context.Context, db *dynamodb.Client, table string, sourceIP string) (allowed bool, retryAfterSeconds int, err error) {
	if sourceIP == "" {
		// Can't identify the caller (e.g. local testing) — fail open rather
		// than blocking legitimate traffic on missing data.
		return true, 0, nil
	}

	now := time.Now().Unix()
	windowStart := now - (now % rateLimitWindowSeconds)
	pk := fmt.Sprintf("ip#%s#%d", sourceIP, windowStart)
	expiresAt := windowStart + rateLimitWindowSeconds + 5 // small buffer past window end

	getOut, getErr := db.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(table),
		Key: map[string]types.AttributeValue{
			"pk": &types.AttributeValueMemberS{Value: pk},
		},
	})
	if getErr != nil {
		return false, 0, getErr
	}
	if getOut.Item != nil {
		if countAttr, ok := getOut.Item["reqCount"].(*types.AttributeValueMemberN); ok {
			if count, convErr := strconv.Atoi(countAttr.Value); convErr == nil && count >= rateLimitMaxRequests {
				return false, rateLimitWindowSeconds, nil
			}
		}
	}

	_, err = db.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(table),
		Key: map[string]types.AttributeValue{
			"pk": &types.AttributeValueMemberS{Value: pk},
		},
		UpdateExpression:    aws.String("ADD reqCount :inc SET expiresAt = if_not_exists(expiresAt, :ttl)"),
		ConditionExpression: aws.String("attribute_not_exists(reqCount) OR reqCount < :limit"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":inc":   &types.AttributeValueMemberN{Value: "1"},
			":ttl":   &types.AttributeValueMemberN{Value: strconv.FormatInt(expiresAt, 10)},
			":limit": &types.AttributeValueMemberN{Value: strconv.Itoa(rateLimitMaxRequests)},
		},
	})

	if err != nil {
		var condFailed *types.ConditionalCheckFailedException
		if errors.As(err, &condFailed) || strings.Contains(err.Error(), "ConditionalCheckFailedException") {
			return false, rateLimitWindowSeconds, nil
		}
		return false, 0, err
	}

	return true, 0, nil
}
