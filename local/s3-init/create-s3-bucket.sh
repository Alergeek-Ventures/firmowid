#!/bin/bash
set -e

BUCKET_NAME="firmowid-uploads"

echo "creating firmowid bucket"

# Create the S3 bucket
awslocal s3 mb "s3://$BUCKET_NAME"

echo "applying CORS configuration"

# Define the CORS configuration
CORS_CONFIGURATION='{
  "CORSRules": [
    {
      "AllowedOrigins": ["http://localhost:4000"],
      "AllowedMethods": ["GET", "POST", "PUT", "DELETE", "HEAD"],
      "AllowedHeaders": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3000
    }
  ]
}'

echo "$CORS_CONFIGURATION" > cors-config.json
awslocal s3api put-bucket-cors --bucket "$BUCKET_NAME" --cors-configuration file://cors-config.json

echo "bucket created"
