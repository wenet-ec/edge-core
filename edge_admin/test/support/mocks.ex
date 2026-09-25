# edge_admin/test/support/mocks.ex
#
# Mox mock modules used by test-environment compile-time adapter injection.
Mox.defmock(EdgeAdmin.NodesMock, for: EdgeAdmin.Nodes)
Mox.defmock(EdgeAdmin.MetadataMock, for: EdgeAdmin.AdminClustering.Metadata)
