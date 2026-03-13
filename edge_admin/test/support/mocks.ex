# edge_admin/test/support/mocks.ex
#
# Mox mock definitions compiled at build time (test env) so Dialyzer can see
# the generated modules and resolve calls in production code that switches on
# Application.compile_env(:edge_admin, :nodes_module) /
# Application.compile_env(:edge_admin, :metadata_module).
Mox.defmock(EdgeAdmin.NodesMock, for: EdgeAdmin.Nodes)
Mox.defmock(EdgeAdmin.MetadataMock, for: EdgeAdmin.Admins.Metadata)
