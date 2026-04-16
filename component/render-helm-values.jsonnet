local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.cloud_provider_openstack;

local renderTolerations(tol) =
  [
    std.prune({ key: k } + tol[k])
    for k in std.objectFields(tol)
    if tol[k] != null
  ];

local ccm_values = params.ccm.helm_values {
  enabledControllers: com.renderArray(params.ccm.enabled_controllers),
  tolerations: renderTolerations(params.ccm.tolerations),
};

local csi_values = params.csi.helm_values {
  csi+: {
    plugin+: {
      controllerPlugin: {
        nodeSelector: std.prune(params.csi.controller_plugin.node_selector),
        tolerations: renderTolerations(params.csi.controller_plugin.tolerations),
      },
      nodePlugin: {
        tolerations: renderTolerations(params.csi.node_plugin.tolerations),
      },
    },
  },
};

{
  'ccm-values': ccm_values,
  'csi-values': csi_values,
}
