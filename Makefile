export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
deploy_public:
	cd tour-app && npm run build	
	aws s3 sync tour-app/dist/ s3://item-backup --delete --endpoint-url http://localhost:4566

deploy_admin:
	cd tour-app/admin && npm run build	
	aws s3 sync tour-app/admin/dist/ s3://item-backup/admin --delete --endpoint-url http://localhost:4566

deploy: deploy_public deploy_admin