# nexmaker/test/nexmaker_test.exs
# Integration tests have been split into focused files:
#
#   test/nexmaker/api_test.exs  — Netmaker REST API (Networks, EnrollmentKeys, Hosts, Nodes, DNS, Server, Superadmin)
#   test/nexmaker/cli_test.exs  — netclient CLI (join, leave, list, ping, health_check, pull)
#
# Pure unit tests:
#   test/nexmaker/cli_parser_test.exs — CliParser (parse_list_output, parse_ping_output, parse_peers_output)
