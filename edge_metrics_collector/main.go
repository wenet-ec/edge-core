// edge_metrics_collector/main.go
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"edge_metrics_collector/internal/config"
	"edge_metrics_collector/internal/server"
	"edge_metrics_collector/internal/vpn"
)

func main() {

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Initialize VPN manager
	vpnManager := vpn.NewManager(cfg.VPN)

	// Initialize server
	srv := server.New(cfg.Server, vpnManager)

	// Start background services
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Start VPN manager background services
	go vpnManager.Start(ctx)

	// Start HTTP server
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	// Wait for interrupt signal
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	<-c


	// Cancel background services
	cancel()

	// Shutdown HTTP server
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	srv.Shutdown(shutdownCtx)

}
