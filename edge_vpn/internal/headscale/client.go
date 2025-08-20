// edge_vpn/internal/headscale/client.go
package headscale

import (
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

// Client handles interactions with Headscale CLI
type Client struct {
	headscalePath string
	headscaleURL  string
	httpClient    *http.Client
}

// NewClient creates a new Headscale client
func NewClient() *Client {
	return &Client{
		headscalePath: "/usr/local/bin/headscale",
		headscaleURL:  "http://localhost:8080",
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// ValidateAPIKey tests if an API key is functional by making actual API calls
func (c *Client) ValidateAPIKey(apiKey string) error {
	if len(apiKey) < 10 || !strings.Contains(apiKey, ".") {
		return fmt.Errorf("API key format appears invalid")
	}

	// Test the key with multiple API endpoints to ensure it's fully functional
	testEndpoints := []string{
		"/api/v1/user",   // List users
		"/api/v1/node",   // List nodes
		"/api/v1/apikey", // List API keys
	}

	var lastErr error
	for i, endpoint := range testEndpoints {
		if err := c.testAPIEndpoint(apiKey, endpoint); err != nil {
			lastErr = err
			// If it's the first attempt and we get connection refused,
			// Headscale might not be ready yet
			if i == 0 && strings.Contains(err.Error(), "connection refused") {
				return fmt.Errorf("headscale not accessible: %w", err)
			}
			// For other errors, continue to next endpoint
			continue
		}
		// If any endpoint succeeds, the key is functional
		return nil
	}

	return fmt.Errorf("API key validation failed on all endpoints, last error: %w", lastErr)
}

// testAPIEndpoint makes a test request to verify the API key works
func (c *Client) testAPIEndpoint(apiKey, endpoint string) error {
	url := c.headscaleURL + endpoint

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	// Read response body for better error reporting
	body, _ := io.ReadAll(resp.Body)

	switch resp.StatusCode {
	case 200:
		return nil
	case 401:
		return fmt.Errorf("unauthorized - API key not recognized by headscale")
	case 403:
		return fmt.Errorf("forbidden - API key lacks permissions")
	case 404:
		return fmt.Errorf("endpoint not found - headscale version mismatch")
	case 500:
		return fmt.Errorf("internal server error: %s", string(body))
	default:
		return fmt.Errorf("unexpected status %d: %s", resp.StatusCode, string(body))
	}
}

// ValidateAPIKeyWithRetry validates the API key with retry logic for startup
func (c *Client) ValidateAPIKeyWithRetry(apiKey string, maxRetries int, delay time.Duration) error {
	var lastErr error

	for attempt := 1; attempt <= maxRetries; attempt++ {
		err := c.ValidateAPIKey(apiKey)
		if err == nil {
			return nil
		}

		lastErr = err

		// Check if this is a retryable error
		if !c.isRetryableError(err) {
			return fmt.Errorf("non-retryable error on attempt %d: %w", attempt, err)
		}

		if attempt < maxRetries {
			time.Sleep(delay)
		}
	}

	return fmt.Errorf("API key validation failed after %d attempts, last error: %w", maxRetries, lastErr)
}

// isRetryableError determines if an error should trigger a retry
func (c *Client) isRetryableError(err error) bool {
	errStr := err.Error()
	// Retry on connection issues, server errors, and auth errors during startup
	// Auth errors during startup might be timing-related (key not yet in database)
	retryablePatterns := []string{
		"connection refused",
		"timeout",
		"internal server error",
		"service unavailable",
		"headscale not accessible",
		"unauthorized", // API key might not be in database yet
		"record not found", // API key might not be in database yet
		"bcrypt", // Hash validation timing issues
	}

	for _, pattern := range retryablePatterns {
		if strings.Contains(errStr, pattern) {
			return true
		}
	}

	return false
}

// Rest of the existing functions remain the same...
func (c *Client) CreateAPIKey(expirationDays int) (string, error) {
	expiration := fmt.Sprintf("%dd", expirationDays)

	cmd := exec.Command(c.headscalePath, "apikeys", "create", "--expiration", expiration)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("failed to create API key: %w, output: %s", err, string(output))
	}

	// Parse the API key from output
	apiKey, err := c.parseAPIKeyFromOutput(string(output))
	if err != nil {
		return "", fmt.Errorf("failed to parse API key from output: %w", err)
	}

	return apiKey, nil
}

// parseAPIKeyFromOutput extracts the API key from CLI output
func (c *Client) parseAPIKeyFromOutput(output string) (string, error) {
	lines := strings.Split(strings.TrimSpace(output), "\n")

	// Try multiple patterns to find the API key
	patterns := []string{
		// Pattern 1: Keys that start with "hs_"
		`hs_[a-zA-Z0-9]+`,
		// Pattern 2: Keys that look like base64/alphanumeric tokens (what we're seeing)
		`[a-zA-Z0-9]{7}\.[a-zA-Z0-9]{32,}`,
		// Pattern 3: Any long alphanumeric string with dots
		`[a-zA-Z0-9]+\.[a-zA-Z0-9]{20,}`,
		// Pattern 4: Just look for the last line if it's a token-like string
		`^[a-zA-Z0-9]+\.[a-zA-Z0-9]+$`,
	}

	for _, pattern := range patterns {
		re := regexp.MustCompile(pattern)
		if matches := re.FindStringSubmatch(output); len(matches) > 0 {
			return matches[0], nil
		}
	}

	// Fallback: if output looks like a single token on the last line
	if len(lines) > 0 {
		lastLine := strings.TrimSpace(lines[len(lines)-1])
		// Check if the last line looks like an API key (has dots and is long enough)
		if strings.Contains(lastLine, ".") && len(lastLine) > 20 && !strings.Contains(lastLine, " ") {
			return lastLine, nil
		}
	}

	return "", fmt.Errorf("no API key found in output: %s", output)
}

// ExpireAPIKey expires an existing API key
func (c *Client) ExpireAPIKey(keyPrefix string) error {
	cmd := exec.Command(c.headscalePath, "apikeys", "expire", keyPrefix)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to expire API key: %w, output: %s", err, string(output))
	}
	return nil
}

// GetKeyPrefix extracts the prefix from a full API key for expiration
func (c *Client) GetKeyPrefix(apiKey string) string {
	// For keys like "XNXjM9T.Y4uBzsFYMfxvEaAPqPGR0kFhEK2yC3Ax"
	// Use the part before the first dot as prefix
	if dotIndex := strings.Index(apiKey, "."); dotIndex > 0 {
		return apiKey[:dotIndex]
	}

	// Fallback: use first 8 characters
	if len(apiKey) > 8 {
		return apiKey[:8]
	}
	return apiKey
}
