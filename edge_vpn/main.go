// edge_vpn/main.go
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type HealthResponse struct {
	Status  string `json:"status"`
	Service string `json:"service"`
	Version string `json:"version"`
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}

	r := chi.NewRouter()

	// Middleware
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.RequestID)

	// Health check
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(HealthResponse{
			Status:  "ok",
			Service: "edge-vpn-wrapper",
			Version: "0.0.1",
		})
	})

	// VPN API routes (to be implemented later)
	r.Route("/api/v1", func(r chi.Router) {
		// Implementation will go here
	})

	log.Printf("Starting Edge VPN Wrapper on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, r))
}
