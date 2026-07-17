# Stores customer enquiry submissions. Configured with a Global Secondary Index (GSI)
# to handle location-based geohash range queries efficiently.
resource "aws_dynamodb_table" "enquiries" {
  name         = "enquiries"
  billing_mode = "PAY_PER_REQUEST" # On-demand pricing ideal for variable traffic

  hash_key = "id"

  # Base table attributes
  attribute {
    name = "id"
    type = "S"
  }

  # Geohash is a fixed-precision string computed from lat/lng by the writer Lambda.
  # Enables query of target cell plus 8 neighbors for exact haversine calculations.
  attribute {
    name = "geohash"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  # Secondary index for geospatial and chronological queries
  global_secondary_index {
    name            = "geohash-index"    
    hash_key        = "geohash"
    range_key       = "createdAt"
    projection_type = "ALL"
  }
}

# 2.2 Rate Limits Table
# A fast, transient store for distributed per-IP rate-limiting.
# Keys are structured as: "ip#<sourceIP>#<windowStart>"
resource "aws_dynamodb_table" "rate_limits" {
  name         = "rate-limits"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # AWS automatically purges stale records using this attribute, saving storage & costs
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }
}
