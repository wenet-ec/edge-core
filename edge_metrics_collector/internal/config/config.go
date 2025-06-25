// edge_metrics_collector/internal/config/config.go
package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	Server ServerConfig
	VPN    VPNConfig
}

type ServerConfig struct {
	Port int
}

type VPNConfig struct {
	URL                  string
	WrapperURL           string
	Username             string
	Hostname             string
	ConnectTimeout       int
	CheckInterval        int
	ReconnectDelay       int
	MaxReconnectAttempts int
}

func Load() (*Config, error) {
	cfg := &Config{
		Server: ServerConfig{
			Port: getEnvInt("SERVER_PORT", 8430),
		},
		VPN: VPNConfig{
			URL:                  getEnvString("VPN_URL", ""),
			WrapperURL:           getEnvString("VPN_WRAPPER_URL", ""),
			Username:             getEnvString("VPN_USERNAME", "edge-metrics"),
			Hostname:             getEnvString("VPN_HOSTNAME", "edge-metrics-collector"),
			ConnectTimeout:       getEnvInt("VPN_CONNECT_TIMEOUT", 30),
			CheckInterval:        getEnvInt("VPN_CHECK_INTERVAL", 30),
			ReconnectDelay:       getEnvInt("VPN_RECONNECT_DELAY", 10),
			MaxReconnectAttempts: getEnvInt("VPN_MAX_RECONNECT_ATTEMPTS", 5),
		},
	}

	// Validate required fields
	if cfg.VPN.URL == "" {
		return nil, fmt.Errorf("VPN_URL environment variable is required")
	}
	if cfg.VPN.WrapperURL == "" {
		return nil, fmt.Errorf("VPN_WRAPPER_URL environment variable is required")
	}

	return cfg, nil
}

func getEnvString(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}
