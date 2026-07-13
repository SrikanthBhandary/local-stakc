BINARY=bootstrap
ZIP=$(notdir $(CURDIR)).zip

build:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o $(BINARY) .

zip: build
	rm -f $(ZIP)
	zip $(ZIP) $(BINARY)

clean:
	rm -f $(BINARY) $(ZIP)