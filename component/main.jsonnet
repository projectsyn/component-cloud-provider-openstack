local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.cloud_provider_openstack;

local renderValue(k, v) =
  if v == null then []
  else if std.isArray(v) then
    [ '%s=%s' % [ k, item ] for item in v if item != null ]
  else if std.isBoolean(v) then
    [ '%s=%s' % [ k, if v then 'true' else 'false' ] ]
  else
    [ '%s=%s' % [ k, std.toString(v) ] ];

local renderSection(name, dict) =
  local lines = std.flattenArrays(
    [ renderValue(k, dict[k]) for k in std.objectFields(dict) ]
  );
  if std.length(lines) == 0 then []
  else [ '[%s]' % name ] + lines + [ '' ];

local renderLBClasses(classes) =
  std.flattenArrays([
    renderSection('LoadBalancerClass "%s"' % cls, classes[cls])
    for cls in std.objectFields(classes)
    if std.length(std.objectFields(classes[cls])) > 0
  ]);

local renderCloudConf() =
  std.join(
    '\n',
    renderSection('Global', params.cloud_conf.global) +
    renderSection('Networking', params.cloud_conf.networking) +
    renderSection('LoadBalancer', params.cloud_conf.load_balancer) +
    renderLBClasses(params.cloud_conf.load_balancer_classes) +
    renderSection('BlockStorage', params.cloud_conf.block_storage) +
    renderSection('Metadata', params.cloud_conf.metadata) +
    renderSection('Route', params.cloud_conf.route)
  );

local secret = kube.Secret(params.cloud_config_secret_name) {
  metadata+: {
    namespace: params.namespace,
  },
  data:: {},
  stringData: {
    'cloud.conf': renderCloudConf(),
  },
};

local scParameters(scDef) =
  local base =
    if params.csi.fs_type != null && params.csi.fs_type != ''
    then { fsType: params.csi.fs_type }
    else {};
  base + scDef.parameters;

local storageClasses = [
  local scDef = params.csi.storage_classes[name];
  sc.storageClass(name) {
    provisioner: 'cinder.csi.openstack.org',
    reclaimPolicy: std.get(scDef, 'reclaim_policy', 'Delete'),
    allowVolumeExpansion: std.get(scDef, 'allow_volume_expansion', true),
    volumeBindingMode: params.csi.volume_binding_mode,
    parameters: scParameters(scDef),
    [if std.length(std.get(scDef, 'allowed_topologies', [])) > 0
    then 'allowedTopologies']:
      scDef.allowed_topologies,
  }
  for name in std.objectFields(params.csi.storage_classes)
];

local volumeSnapshotClasses = [
  local vsc = params.csi.volume_snapshot_classes[name];
  kube._Object('snapshot.storage.k8s.io/v1', 'VolumeSnapshotClass', name) {
    driver: 'cinder.csi.openstack.org',
    deletionPolicy: vsc.deletion_policy,
    [if std.length(vsc.parameters) > 0 then 'parameters']: vsc.parameters,
  }
  for name in std.objectFields(params.csi.volume_snapshot_classes)
];

{
  [if params.namespace != 'kube-system' then '00_namespace']:
    kube.Namespace(params.namespace),
  '01_secret': secret,
  [if std.length(params.csi.storage_classes) > 0 then '10_storageclasses']:
    storageClasses,
  [if std.length(params.csi.volume_snapshot_classes) > 0
  then '10_volumesnapshotclasses']:
    volumeSnapshotClasses,
}
