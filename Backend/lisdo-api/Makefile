PACKAGE_ZIP := $(abspath ../../Infra/aws/build/lisdo-api.zip)
PACKAGE_DIR := $(abspath .build/lambda-package)
PYTHON ?= python3
LAMBDA_PLATFORM ?= manylinux2014_aarch64
LAMBDA_PYTHON_VERSION ?= 3.12
LAMBDA_PYTHON_ABI ?= cp312
LAMBDA_REQUIREMENTS := $(abspath requirements-lambda.txt)

.PHONY: package clean-package

package:
	rm -rf "$(PACKAGE_DIR)"
	mkdir -p "$(PACKAGE_DIR)"
	$(PYTHON) -m pip install --quiet --target "$(PACKAGE_DIR)" --platform "$(LAMBDA_PLATFORM)" --python-version "$(LAMBDA_PYTHON_VERSION)" --implementation cp --abi "$(LAMBDA_PYTHON_ABI)" --only-binary=:all: -r "$(LAMBDA_REQUIREMENTS)"
	cp -R src/lisdo_api "$(PACKAGE_DIR)/lisdo_api"
	mkdir -p "$(dir $(PACKAGE_ZIP))"
	rm -f "$(PACKAGE_ZIP)"
	cd "$(PACKAGE_DIR)" && zip -rq "$(PACKAGE_ZIP)" . -x '*/__pycache__/*' '*.pyc' '*.pyo' '*.dist-info/RECORD'
	@echo "Wrote $(PACKAGE_ZIP)"

clean-package:
	rm -rf "$(PACKAGE_DIR)"
	rm -f "$(PACKAGE_ZIP)"
