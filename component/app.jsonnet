local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.cloud_provider_openstack;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('cloud-provider-openstack', params.namespace.name);

local appPath =
  local project = std.get(std.get(app, 'spec', {}), 'project', 'syn');
  if project == 'syn' then 'apps' else 'apps-%s' % project;

{
  ['%s/cloud-provider-openstack' % appPath]: app,
}
