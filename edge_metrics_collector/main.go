// edge_metrics_collector/main.go
package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

type HealthResponse struct {
	Status        string `json:"status"`
	Timestamp     string `json:"timestamp"`
	VPNConnected  bool   `json:"vpn_connected"`
	VMAgentStatus string `json:"vmagent_status"`
}

type VPNStatus struct {
	Connected bool   `json:"connected"`
	IP        string `json:"ip,omitempty"`
	Error     string `json:"error,omitempty"`
}

func main() {
	log.Println("Starting Edge Metrics Collector service...")

	// TODO: Add VPN connection management logic here
	// TODO: Add vmagent process management logic here
	// TODO: Add VPN reconnection logic here

	mux := http.NewServeMux()

	// Health endpoint
	mux.HandleFunc("/health", healthHandler)

	// VPN status endpoint (for future use)
	mux.HandleFunc("/vpn/status", vpnStatusHandler)

	server := &http.Server{
		Addr:    ":8430",
		Handler: mux,
	}

	// Start server in goroutine
	go func() {
		log.Println("Starting HTTP server on :8430")
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	// Wait for interrupt signal
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	<-c

	log.Println("Shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Printf("Server shutdown error: %v", err)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	response := HealthResponse{
		Status:        "ok",
		Timestamp:     time.Now().UTC().Format(time.RFC3339),
		VPNConnected:  false,             // TODO: Check actual VPN status
		VMAgentStatus: "not_implemented", // TODO: Check vmagent status
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func vpnStatusHandler(w http.ResponseWriter, r *http.Request) {
	status := VPNStatus{
		Connected: false, // TODO: Implement actual VPN status check
		Error:     "not_implemented",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}
