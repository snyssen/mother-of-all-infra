# Plans

Designs and runbooks for work that has **not been carried out yet**. Nothing in this
section describes the infrastructure as it is: check the code before relying on any of it.

Once a plan is carried out, it leaves this section. Either it is deleted, with what still
matters folded into the regular pages (architecture, operations, services), or, when the
record of decisions is worth keeping, it moves to the [Archive](../archive/index.md) with
an obsolete banner.

- **[CrowdSec AppSec on ingress](crowdsec-appsec.md)** — putting CrowdSec's WAF in front
  of every public route, at the ingress host, with apps-01's engine doing the inspection.
  Not started.
- **[Rootless containers](rootless-containers.md)** — getting apps-01's containers off
  root (issue #322): first non-root under today's Docker, then a choice of rootless
  runtime. Inventory drafted.
