// edge_metrics_collector/internal/vpn/tailscale_client.go
package vpn

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"edge_metrics_collector/internal/config"
)

type TailscaleClient struct {
	config config.VPNConfig
}

type TailscaleStatus struct {
	VPNIp       string `json:"vpn_ip"`
	VPNHostname string `json:"vpn_hostname"`
	Connected   bool   `json:"connected"`
}

type PreAuthKeyResponse struct {
	PreAuthKey struct {
		Key        string `json:"key"`
		ID         string `json:"id"`
		Reusable   bool   `json:"reusable"`
		Ephemeral  bool   `json:"ephemeral"`
		Used       bool   `json:"used"`
		Expiration string `json:"expiration"`
		CreatedAt  string `json:"createdAt"`
	} `json:"preAuthKey"`
}

type UserListResponse struct {
	Users []UserResponse `json:"users"`
}

type UserResponse struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Email     string `json:"email"`
	CreatedAt string `json:"createdAt"`
}

const (
	tailscaleStateDir  = "/var/lib/tailscale"
	tailscaleStateFile = "/var/lib/tailscale/tailscaled.state"
	tailscaleSocket    = "/var/run/tailscale/tailscaled.sock"
	tailscaleCacheDir  = "/var/cache/tailscale"
)

func NewTailscaleClient(cfg config.VPNConfig) *TailscaleClient {
	return &TailscaleClient{
		config: cfg,
	}
}

func (c *TailscaleClient) Connect() error {
	// Ensure daemon is running first
	if err := c.ensureDaemonRunning(); err != nil {
		return fmt.Errorf("failed to ensure daemon running: %w", err)
	}

	// Check if already connected
	if connected, err := c.isAlreadyConnected(); err == nil && connected {
		log.Println("Tailscale: Already connected")
		return nil
	}

	// Get enrollment key
	enrollmentKey, err := c.getEnrollmentKey()
	if err != nil {
		return fmt.Errorf("failed to get enrollment key: %w", err)
	}

	// Connect with enrollment key
	return c.connectWithKey(enrollmentKey)
}

func (c *TailscaleClient) Disconnect() error {
	cmd := exec.Command("tailscale", "down")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("tailscale down failed: %w, output: %s", err, string(output))
	}
	return nil
}

func (c *TailscaleClient) GetStatus() (*TailscaleStatus, error) {
	cmd := exec.Command("tailscale", "status", "--json")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("tailscale status failed: %w, output: %s", err, string(output))
	}

	var statusData map[string]interface{}
	if err := json.Unmarshal(output, &statusData); err != nil {
		return nil, fmt.Errorf("failed to parse tailscale status: %w", err)
	}

	status := &TailscaleStatus{
		Connected: false,
	}

	// Extract VPN IP and hostname from status
	if self, ok := statusData["Self"].(map[string]interface{}); ok {
		if tailscaleIPs, ok := self["TailscaleIPs"].([]interface{}); ok && len(tailscaleIPs) > 0 {
			if ip, ok := tailscaleIPs[0].(string); ok {
				status.VPNIp = ip
				status.Connected = true
			}
		}
		if hostInfo, ok := self["HostInfo"].(map[string]interface{}); ok {
			if hostname, ok := hostInfo["Hostname"].(string); ok {
				status.VPNHostname = hostname
			}
		}
	}

	return status, nil
}

// ensureDaemonRunning starts tailscaled if it's not already running
func (c *TailscaleClient) ensureDaemonRunning() error {
	// Check if daemon is already running
	cmd := exec.Command("tailscale", "status")
	_, err := cmd.CombinedOutput()
	if err == nil {
		log.Println("Tailscale: Daemon already running")
		return nil
	}

	log.Println("Tailscale: Starting daemon")
	return c.startDaemon()
}

// startDaemon starts the tailscaled daemon
func (c *TailscaleClient) startDaemon() error {
	// Ensure directories exist
	if err := c.ensureDirectories(); err != nil {
		return fmt.Errorf("failed to create directories: %w", err)
	}

	// Start tailscaled daemon in background (like Elixir's spawn)
	cmd := exec.Command("tailscaled",
		fmt.Sprintf("--state=%s", tailscaleStateFile),
		fmt.Sprintf("--socket=%s", tailscaleSocket),
	)

	// Start daemon in background and don't wait for it to finish
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start tailscaled: %w", err)
	}

	// Wait for daemon to be ready (like Elixir's :timer.sleep(2000))
	log.Println("Tailscale: Waiting for daemon to be ready...")
	time.Sleep(2 * time.Second)

	log.Println("Tailscale: Daemon started")
	return nil
}

// ensureDirectories creates required directories
func (c *TailscaleClient) ensureDirectories() error {
	dirs := []string{
		tailscaleStateDir,
		tailscaleCacheDir,
		"/var/run/tailscale",
	}

	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", dir, err)
		}
	}

	return nil
}

func (c *TailscaleClient) isAlreadyConnected() (bool, error) {
	cmd := exec.Command("tailscale", "status")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return false, nil // Not connected or error
	}

	outputStr := string(output)
	hasHostname := strings.Contains(outputStr, c.config.Hostname)
	hasVPNIP := regexp.MustCompile(`100\.\d+\.\d+\.\d+`).MatchString(outputStr)

	return hasHostname && hasVPNIP, nil
}

func (c *TailscaleClient) getEnrollmentKey() (string, error) {
	// Get user ID
	userID, err := c.getUserID()
	if err != nil {
		return "", fmt.Errorf("failed to get user ID: %w", err)
	}

	// Get preauth key
	return c.getPreAuthKey(userID)
}

func (c *TailscaleClient) getUserID() (string, error) {
	url := fmt.Sprintf("%s/api/v1/user?name=%s", c.config.WrapperURL, c.config.Username)

	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("failed to get user: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	// Parse the ListUsersResponse format
	var userListResp UserListResponse
	if err := json.Unmarshal(body, &userListResp); err != nil {
		return "", fmt.Errorf("failed to parse user list response: %w", err)
	}

	// Find the user with matching name
	for _, user := range userListResp.Users {
		if user.Name == c.config.Username {
			return user.ID, nil
		}
	}

	return "", fmt.Errorf("user %s not found", c.config.Username)
}

func (c *TailscaleClient) getPreAuthKey(userID string) (string, error) {
	url := fmt.Sprintf("%s/api/v1/preauthkey", c.config.WrapperURL)

	expiration := time.Now().Add(1 * time.Hour).Format(time.RFC3339)

	reqBody := map[string]interface{}{
		"user":       userID,
		"reusable":   false,
		"ephemeral":  false,
		"expiration": expiration,
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		return "", fmt.Errorf("failed to get preauth key: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	var keyResp PreAuthKeyResponse
	if err := json.Unmarshal(body, &keyResp); err != nil {
		return "", fmt.Errorf("failed to parse preauth key response: %w", err)
	}

	if keyResp.PreAuthKey.Key == "" {
		return "", fmt.Errorf("failed to get preauth key from response: %s", string(body))
	}

	return keyResp.PreAuthKey.Key, nil
}

func (c *TailscaleClient) connectWithKey(enrollmentKey string) error {
	args := []string{
		"up",
		fmt.Sprintf("--login-server=%s", c.config.URL),
		fmt.Sprintf("--authkey=%s", enrollmentKey),
		"--accept-dns=false",
		fmt.Sprintf("--hostname=%s", c.config.Hostname),
	}

	cmd := exec.Command("tailscale", args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("tailscale up failed: %w, output: %s", err, string(output))
	}

	log.Printf("Tailscale: Connected successfully with hostname %s", c.config.Hostname)
	return nil
}
