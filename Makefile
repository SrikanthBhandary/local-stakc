export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
deploy_public:
	cd tour-app && npm run build	
	aws s3 sync tour-app/dist/ s3://www.highpasses.com --delete --endpoint-url http://localhost:4566

deploy_admin:
	cd tour-app/admin && npm run build	
	aws s3 sync tour-app/admin/dist/ s3://www.highpasses.com/admin --delete --endpoint-url http://localhost:4566

lambda_reader:
	cd lambda/reader && make clean && make zip

lambda_writer:
	cd lambda/writer && make clean && make zip

lambda_processor:
	cd lambda/processor && make clean && make zip

bundle_lambda: lambda_reader lambda_writer lambda_processor

deploy: deploy_public deploy_admin