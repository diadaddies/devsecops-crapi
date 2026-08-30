COMPOSE = docker compose -f target/docker-compose.yml
TARGET  = http://127.0.0.1:8888

.PHONY: help up up-full down status logs wait dast zap attack-info clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}'

up: ## Deploy crAPI, low-RAM stack (chatbot stubbed, no chromadb)
	$(COMPOSE) --profile lean up -d
	@echo "crAPI starting (low-RAM) -> $(TARGET)  (mail UI: http://127.0.0.1:8025)"

up-full: ## Deploy crAPI with the AI chatbot + chromadb (heavy)
	$(COMPOSE) --profile full up -d
	@echo "crAPI starting (full) -> $(TARGET)"

down: ## Stop crAPI and free RAM
	$(COMPOSE) down

status: ## Show container status
	$(COMPOSE) ps

logs: ## Tail logs
	$(COMPOSE) logs -f --tail=100

wait: ## Block until crAPI answers on :8888
	@for i in $$(seq 1 60); do \
	  c=$$(curl -s -o /dev/null -w '%{http_code}' $(TARGET)/ || true); \
	  [ "$$c" = "200" ] || [ "$$c" = "302" ] && { echo "up ($$c)"; exit 0; }; \
	  echo "waiting ($$i) $$c"; sleep 5; done; echo "timeout"; exit 1

dast: wait ## Run the same nuclei scan the pipeline runs
	@mkdir -p reports
	nuclei -u $(TARGET) -t security/nuclei-templates/ \
	  -tags exposure,misconfig,default-login \
	  -severity low,medium,high,critical -o reports/nuclei-report.txt -stats || true
	@echo "---"; cat reports/nuclei-report.txt || true

zap: wait ## Run the OWASP ZAP baseline scan (same as the pipeline)
	@mkdir -p reports
	docker run --rm --network host -v "$$PWD/reports:/zap/wrk/:rw" \
	  ghcr.io/zaproxy/zaproxy:stable \
	  zap-baseline.py -t $(TARGET) \
	    -r zap-baseline.html -w zap-baseline.md -x zap-baseline.xml -I || true
	@echo "---"; echo "reports/zap-baseline.html"

attack-info: ## Print manual-attack starting points
	@echo "Web/app:   $(TARGET)"
	@echo "Mail (OTP): http://127.0.0.1:8025"
	@echo "Try:       sqlmap -u '$(TARGET)/...' | ffuf -w wordlist -u $(TARGET)/FUZZ | Burp proxy"

clean: down ## Stop and remove volumes (full reset)
	$(COMPOSE) down -v
