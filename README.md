# Ansible for Kubernetes — a hands-on demo

Five small playbooks showing where Ansible genuinely helps in a Kubernetes shop:
managing resources and Helm releases as idempotent tasks, treating pods as ordinary
managed hosts, discovering pods at runtime, and fanning one playbook out over several
clusters. Everything runs on two local [kind](https://kind.sigs.k8s.io/) clusters and
is built on the [`kubernetes.core`](https://github.com/ansible-collections/kubernetes.core)
collection.

Ansible is not a GitOps replacement: a controller reconciles continuously *inside* one
cluster, Ansible converges on demand *across* boundaries — many clusters plus everything
around them (DNS, load balancers, VMs, clouds, secrets). This repo demonstrates the
second half.

## Requirements

| | |
|---|---|
| Tools | `docker`, `kind`, `kubectl`, `helm`, `python3` ≥ 3.10 with `venv` |
| RAM | ~6 GB free for two kind clusters |
| Ansible | **not** a prerequisite — installed into a local `./.venv` by the setup script |
| Time | ~5 min setup, ~20 min to walk through all five playbooks |

`ansible-core` ≥ 2.16, `kubernetes.core` ≥ 6.0.0 (≥ 6.5.0 if you want Helm v4) and the
Python `kubernetes` client are pinned in `requirements.yml` / `requirements.txt`.

## Quickstart

```bash
git clone https://github.com/yurnov/ansible-for-kubernetes-demo
cd ansible-for-kubernetes-demo

./scripts/00-prereqs.sh      # tells you exactly what is missing
./scripts/01-setup.sh        # .venv + two kind clusters + preloaded images (~3-5 min)
source .venv/bin/activate

ansible-playbook playbooks/01-resources.yml
```

The setup script creates the clusters `site-a` and `site-b`, writes their kubeconfigs to
`.kube/`, preloads the container images into both clusters and pre-pulls the podinfo Helm
chart into `.charts/`, so the whole demo also works without network access afterwards.

Run every playbook from the repository root — that is where `ansible.cfg` lives. A second
terminal with `watch kubectl --kubeconfig .kube/site-a.yaml get pods -n demo` makes the
effects visible while Ansible output scrolls by.

When you are done: `./scripts/99-teardown.sh` deletes both clusters and the generated files.

## Walkthrough

### 1. Resources — `playbooks/01-resources.yml`

```bash
ansible-playbook playbooks/01-resources.yml
ansible-playbook playbooks/01-resources.yml            # again: changed=0, idempotent
ansible-playbook playbooks/01-resources.yml -e web_replicas=5 --check --diff
```

One play (`hosts: sites`) configures both clusters in parallel; each host carries its own
kubeconfig and `module_defaults` injects it into every `k8s` task. The Deployment comes
from a Jinja2 template, `wait: true` blocks until the rollout is finished, and
`--check --diff` previews a change without applying it — something `kubectl` has no real
equivalent for.

Try `-e web_image=nginx:1.26-alpine` (that image is not preloaded into kind, so the
rollout needs network to pull it).

### 2. Helm — `playbooks/02-helm.yml`

```bash
ansible-playbook playbooks/02-helm.yml
ansible-playbook playbooks/02-helm.yml -e podinfo_message='hello from my laptop'
```

`helm_repository` + `helm` + `helm_info`. First run installs, the second upgrades because a
value changed, a third with the same value changes nothing. Values are plain Ansible
variables, so per-site configuration is free.

See the result: `kubectl --kubeconfig .kube/site-a.yaml -n demo port-forward deploy/podinfo 9898:9898`
and open <http://localhost:9898>.

Without network, use the pre-pulled chart:
`-e podinfo_chart_ref=$PWD/.charts/podinfo-6.7.1.tgz`

### 3. Pods as managed hosts — `playbooks/03-pods-as-hosts.yml`

```bash
ansible-playbook playbooks/03-pods-as-hosts.yml
```

The `workers` inventory group is made of **pods**, reached with
`ansible_connection: kubernetes.core.kubectl` — `ping`, `copy` and `command` execute inside
the containers, and the whole module ecosystem comes with them.

The rule to remember: modules need Python in the image; `raw` and `script` need only a
shell; with neither, drive the pod from outside via `k8s_exec`. The last play proves it
against the python-less nginx pod, where `ping` fails on purpose.

Ad-hoc works too: `ansible worker-site-a -m ansible.builtin.command -a "python3 --version"`

### 4. Runtime discovery — `playbooks/04-dynamic-hosts.yml`

```bash
ansible-playbook playbooks/04-dynamic-hosts.yml
ansible-playbook playbooks/04-dynamic-hosts.yml -e fleet_replicas=3
```

Deployment-managed pods have generated names, so no static inventory can list them.
`k8s_info` finds them mid-play, `add_host` registers each as an in-memory host, and the
second play then runs inside every discovered pod across both clusters. This is the
official replacement for the `k8s` inventory plugin removed in `kubernetes.core` 6.0.0.

The `serial: 1` in the first play is not decoration: `add_host` runs once per play batch,
so without it only the first site's pods would be registered.

### 5. Site-aware execution — `playbooks/05-site-aware.yml`

```bash
THIS_SITE_NAME=site-a ansible-playbook playbooks/05-site-aware.yml
THIS_SITE_NAME=site-b ansible-playbook playbooks/05-site-aware.yml   # outputs invert
```

Requires the worker pods from playbook 03.

One task, two execution locations, decided at runtime by a `ternary` on
`ansible_connection`: the site you are *at* reports `LOCAL` and your machine's hostname,
every other site reports `IN-POD` and the pod's name. Switch the Python interpreter
together with the connection, or the module fails with rc=127.

The last two tasks show the difference everybody gets wrong: `environment:` sets variables
**inside** the pod, while `ansible_kubectl_local_env_vars` sets them for the **local**
`kubectl` process on the controller — which is how exec-based auth (`aws eks get-token`,
`gcloud`, `kubelogin`) receives its credentials.

## Layout

```
ansible.cfg          run playbooks from the repository root
inventory/sites.yml  two sites (kind clusters) + pods as static hosts
templates/           Jinja2-templated Kubernetes manifests
playbooks/           the five playbooks above
scripts/             00-prereqs.sh · 01-setup.sh · 99-teardown.sh
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ansible-playbook: command not found` | `source .venv/bin/activate` (created by `./scripts/01-setup.sh`) |
| `Failed to import the required Python library (kubernetes)` | activate the venv, or `pip install -r requirements.txt` into the interpreter Ansible uses (`ansible --version` shows it) |
| `couldn't resolve module/action kubernetes.core.k8s` | `ansible-galaxy collection install -r requirements.yml` with the venv active |
| kind create hangs / node NotReady | Docker needs more resources; give it ≥ 6 GB RAM and rerun `./scripts/01-setup.sh` |
| `error: unable to upgrade connection` on kubectl-connection tasks | worker pod not Ready yet — rerun playbook 03; or the kubeconfig is stale — rerun `./scripts/01-setup.sh` |
| Playbook 02 cannot resolve the chart repo | no network — use the local tarball fallback shown above |
| Playbook 05: `list index out of range` | worker pods missing — run playbook 03 first |
| `module interpreter ... not found`, rc=127 | set `ansible_python_interpreter` together with the connection switch (see playbook 05) |
| `DEPRECATION WARNING: Direct access to the environment attribute` | comes from inside `kubernetes.core`, not from these playbooks — harmless with recent ansible-core |

## License

Apache-2.0 — see [LICENSE](LICENSE). Copy anything here into your own playbooks.
