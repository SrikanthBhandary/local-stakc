package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

const dedupCooldownSeconds = 300 // 5 minutes

// dedupKey derives a stable key for "this person enquiring about this tour",
// independent of the client-generated enquiry id — which changes on every
// submit, so on its own it can't catch someone resubmitting the same form
// (double-click, hitting back and resubmitting, panic-clicking because
// nothing visibly happened, etc).
func dedupKey(email, tour string) string {
	normalized := strings.ToLower(strings.TrimSpace(email)) + "|" + strings.ToLower(strings.TrimSpace(tour))
	sum := sha256.Sum256([]byte(normalized))
	return hex.EncodeToString(sum[:])
}

// checkDuplicateSubmission claims a short-lived slot for (email, tour) via a
// conditional PutItem. If the slot's already taken, this exact (email, tour)
// pair was submitted within the last dedupCooldownSeconds — treat it as a
// duplicate rather than creating a second enquiry record.
//
// Reuses the same table as the rate limiter (distinguished by the "dedupe#"
// key prefix vs the limiter's "ip#" prefix) rather than provisioning a
// separate table for what's functionally the same kind of short-lived,
// TTL-expiring claim.
func checkDuplicateSubmission(ctx context.Context, db *dynamodb.Client, table, email, tour string) (isDuplicate bool, err error) {
	pk := fmt.Sprintf("dedupe#%s", dedupKey(email, tour))
	expiresAt := time.Now().Unix() + dedupCooldownSeconds

	_, err = db.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(table),
		Item: map[string]types.AttributeValue{
			"pk":        &types.AttributeValueMemberS{Value: pk},
			"expiresAt": &types.AttributeValueMemberN{Value: strconv.FormatInt(expiresAt, 10)},
		},
		ConditionExpression: aws.String("attribute_not_exists(pk)"),
	})

	if err != nil {
		var condFailed *types.ConditionalCheckFailedException
		if errors.As(err, &condFailed) || strings.Contains(err.Error(), "ConditionalCheckFailedException") {
			return true, nil
		}
		return false, err
	}

	return false, nil
}
