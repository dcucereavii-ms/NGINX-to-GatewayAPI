# Ingress controller options for AKS — replacing NGINX

**Audience**: architects/leads deciding which ingress stack to standardise on
after moving off the community **ingress-nginx** controller.
**Scope**: AKS-focused. Mixes Microsoft-supported options and third-party
controllers that run well on AKS. Generic Kubernetes controllers that have
no AKS-specific integration story (Skipper, Voyager, Kong DB-backed mode,
etc.) are intentionally omitted.

---

## TL;DR — pick one based on the dominant requirement

| If your top priority is… | Recommended option |
|---|---|
| Microsoft-supported, lowest day-2 cost, Gateway API native | **App Routing add-on (Istio Gateway API)** ⭐ — what this POC uses |
| Microsoft-supported, L7 in **Azure** (not in cluster), WAF | **Application Gateway for Containers (AGC)** |
| Microsoft-supported, classic AppGw resource, mature | **AGIC (App Gateway Ingress Controller)** |
| Drop-in NGINX, same config knobs, OSS, free | **ingress-nginx (community)** or **NGINX Inc.** |
| Mature service mesh + ingress in one product | **Istio (self-managed) / Cilium / Linkerd+Gateway** |
| Best-in-class API gateway features (rate-limit, auth, plugins) | **Kong** or **Traefik** |
| Edge L7 + CDN + DDoS in front of AKS | **Front Door** (Azure-managed, not in-cluster) |

---

## Comparison matrix

Legend: ✅ first-class · 🟡 possible with work · ❌ not supported.

| Option | MS-supported | Runs… | Gateway API | Ingress v1 | TLS from Key Vault | WAF | mTLS / mesh | Private IP | Multi-tenant friendly | Cost model |
|---|---|---|---|---|---|---|---|---|---|---|
| **App Routing add-on (Istio Gateway API)** ⭐ | ✅ (AKS add-on) | In-cluster | ✅ native | ✅ (via NGINX sub-add-on) | ✅ CSI driver | 🟡 via AGC/Front Door in front | ✅ (Istio mTLS) | ✅ annotation | ✅ ReferenceGrants | Free add-on; pay for LB + nodes |
| **Application Gateway for Containers (AGC)** | ✅ (GA) | Azure PaaS | ✅ native | ❌ | ✅ via Frontends | ✅ WAF SKU | ❌ (terminates at edge) | ✅ private frontend | 🟡 one AGC per workspace | Per-AGC + per-LCU; no node cost |
| **AGIC (AppGw Ingress Controller)** | ✅ (mature) | Controller in-cluster, LB in Azure | ❌ | ✅ | 🟡 via cert URI ref | ✅ WAF on AppGw | ❌ | ✅ private AppGw | ❌ one AppGw per cluster | AppGw v2 hourly + CU |
| **ingress-nginx (community)** | ❌ (OSS only) | In-cluster | ❌ | ✅ | 🟡 via CSI driver | 🟡 ModSecurity (deprecated upstream) | ❌ | ✅ Service annotation | 🟡 IngressClass / namespace split | Free; pay for LB + nodes |
| **NGINX Inc. (commercial / NIC)** | ❌ (3P paid) | In-cluster | ✅ (NGF) | ✅ | 🟡 via CSI | ✅ NGINX App Protect (paid) | 🟡 with NGINX Service Mesh | ✅ | ✅ | License + nodes + LB |
| **Istio (self-managed, OSS)** | ❌ | In-cluster | ✅ native | 🟡 | 🟡 | 🟡 with WASM/ext-authz | ✅ mTLS | ✅ | ✅ | Free OSS; high ops cost |
| **Cilium Gateway / Ingress** | ❌ on AKS today | In-cluster (CNI-based) | ✅ | ✅ | 🟡 | 🟡 | ✅ via Cilium mTLS | ✅ | ✅ | Free OSS; pay nodes |
| **Traefik Proxy** | ❌ | In-cluster | ✅ (v3) | ✅ | 🟡 | ❌ | ❌ | ✅ | ✅ | OSS free; Traefik Hub paid |
| **Kong Ingress Controller** | ❌ | In-cluster | ✅ | ✅ | 🟡 | ❌ (Kong Gateway plugins) | 🟡 | ✅ | ✅ | OSS free; Kong Enterprise paid |
| **HAProxy Ingress / HAProxy Tech** | ❌ | In-cluster | 🟡 (alpha) | ✅ | 🟡 | ✅ (HAProxy Enterprise) | ❌ | ✅ | ✅ | OSS free; Enterprise paid |
| **Envoy Gateway (OSS)** | ❌ | In-cluster | ✅ native | 🟡 | 🟡 | 🟡 (ext-proc) | ✅ via Envoy | ✅ | ✅ | Free OSS; pay nodes |
| **Azure Front Door (Standard/Premium)** | ✅ | Azure global edge | ❌ | ❌ | ✅ managed certs | ✅ WAF Premium | ❌ | ❌ (public only) | 🟡 routes per domain | Per-request + data |

---

## Microsoft options

### 1. App Routing add-on — Istio Gateway API (this POC) ⭐
Managed Gateway API implementation on AKS. `gatewayClassName: approuting-istio`.

**Pros**
- AKS add-on; no controllers to install or upgrade yourself.
- Native **Gateway API** — the upstream-blessed successor to Ingress.
- Free; integrates with **Key Vault CSI** out of the box.
- Same data plane (Istio/Envoy) used by huge production fleets.
- Works with both public and **internal** LBs (this repo's §7.4).
- mTLS / mesh upgrade path is the same tech stack.

**Cons**
- Newer than alternatives — fewer Stack Overflow hits, some niche
  features (e.g. raw TCP listeners) are limited.
- Locked to AKS lifecycle; can't run it off-Azure unchanged.
- Doesn't include WAF — pair with AGC or Front Door if needed.

### 2. Application Gateway for Containers (AGC)
Azure PaaS L7 with Gateway API CRDs in the cluster but data plane in Azure.

**Pros**
- L7 lives **outside** the cluster — node failures / upgrades don't affect ingress.
- Native **WAF**, autoscaling, request-level metering.
- Gateway API native; ALB Controller is the only thing in-cluster.
- Backed by Microsoft SLA.

**Cons**
- Newer Azure service — fewer features than mature AppGw v2 (still closing the gap).
- One AGC per workspace; not free (per-LCU billing).
- No in-cluster mTLS termination.

### 3. AGIC (App Gateway Ingress Controller) — Ingress-only
The classic option: controller syncs `Ingress` objects into an Application
Gateway v2.

**Pros**
- Mature, GA for years; well-documented patterns.
- WAF v2, autoscaling, public **or** private AppGw.
- Strong Azure RBAC + Private Link integration.

**Cons**
- **Ingress v1 only** — no Gateway API, no namespace-decoupled cert refs.
- One AppGw per cluster; cross-team noisy-neighbour risk.
- Slow apply loop on large clusters (full AppGw config regeneration).
- Microsoft is steering new investment to **AGC** for net-new workloads.

### 4. Azure Front Door (not a Kubernetes controller, but worth listing)
Global edge L7 in front of any origin, including an AKS LB.

**Pros**
- Global anycast, CDN, **WAF Premium**, DDoS, managed certs.
- Decouples public surface from cluster lifecycle entirely.

**Cons**
- Not a Kubernetes-aware ingress — you still need *something* in/at the cluster.
- Public-only; no private-VNet origin path without Private Link Service.
- Per-request billing can add up at scale.

---

## Third-party / OSS options

### 5. ingress-nginx (community)
Your current controller.

**Pros**
- Ubiquitous; every Helm chart and SO answer assumes it.
- Free; runs anywhere.
- Predictable behaviour, hot reload via templates.

**Cons**
- **Ingress v1 only** — Gateway API support is not on the roadmap.
- ModSecurity WAF was **deprecated upstream** in 2024.
- Annotation sprawl for non-trivial routing.
- CVE cadence is high; you own the upgrade pipeline.
- Not Microsoft-supported.

### 6. NGINX Inc. — NGINX Ingress Controller (NIC) / NGINX Gateway Fabric (NGF)
Commercial NGINX from F5. Different codebase from community.

**Pros**
- Backed by F5 with paid SLA; NGINX App Protect WAF.
- NGF is a clean Gateway API implementation (no Ingress-isms).
- Familiar config language if your team already knows NGINX.

**Cons**
- License cost; AGC/App Routing are free or pay-per-use.
- Two products (NIC vs NGF) — picking the right one isn't obvious.
- Not Microsoft-supported (F5 owns the support contract).

### 7. Istio (self-managed)
What App Routing wraps — but you run the control plane yourself.

**Pros**
- Maximum control: any Envoy feature, any Istio policy.
- Full service mesh, mTLS, multi-cluster, ambient mode.
- Vendor-neutral; portable off Azure.

**Cons**
- Operational burden: CRDs, sidecars/ambient, control-plane HA, upgrades.
- You become the on-call for ingress + mesh.
- Most teams adopting Istio on AKS today simply enable the **Istio add-on**
  or App Routing — running it bare is harder to justify.

### 8. Cilium Gateway / Cilium Ingress
Gateway API implementation built into Cilium (eBPF data plane).

**Pros**
- No separate proxy pod — eBPF in the kernel; very low latency.
- Unified with Cilium network policies and observability (Hubble).
- Gateway API native.

**Cons**
- AKS doesn't ship a Cilium-based dataplane that exposes the
  Gateway/Ingress features by default; using it means **Azure CNI powered
  by Cilium** + opt-in flags or a community install.
- Smaller knowledge base than Istio/NGINX.
- Not Microsoft-supported as an ingress.

### 9. Traefik Proxy
Popular OSS edge router; Gateway API in v3.

**Pros**
- Excellent UX: file/CRD/k8s providers, built-in dashboard.
- Native Let's Encrypt, automatic cert reload.
- Good fit for dynamic microservice / Docker-style environments.

**Cons**
- No first-class WAF (need a sidecar like Coraza).
- Performance is fine but not best-in-class at very high RPS.
- Not Microsoft-supported.

### 10. Kong Ingress Controller
Kong Gateway in front of upstreams, controlled via CRDs / Ingress / Gateway API.

**Pros**
- Best-in-class API gateway features: rate limiting, JWT, OIDC, key auth,
  request transformation, dozens of plugins.
- Strong dev portal / API management story (Kong Konnect).

**Cons**
- Heavier than NGINX/Traefik for plain HTTP routing.
- Many high-value features sit behind Kong Enterprise.
- Not Microsoft-supported.

### 11. HAProxy Ingress (community) / HAProxy Enterprise Kubernetes Ingress
HAProxy as the data plane.

**Pros**
- Extremely fast, low memory; gold-standard L4/L7 metrics.
- HAProxy Enterprise adds WAF, bot management, paid support.

**Cons**
- Gateway API support is alpha/limited.
- Smaller AKS-specific community than NGINX/Traefik.
- Not Microsoft-supported.

### 12. Envoy Gateway (OSS)
Upstream Envoy project's own Gateway API implementation.

**Pros**
- Pure Envoy, no Istio overhead — lighter than Istio for ingress-only use.
- Gateway API native, governed by the same community.
- Strong roadmap, CNCF-backed.

**Cons**
- Younger than Istio/NGINX; smaller production footprint.
- No bundled WAF or auth — bring your own filters.
- Not Microsoft-supported.

---

## How to choose (decision flow)

1. **Do you need Microsoft support / SLA on the ingress itself?**
   - Yes → App Routing (Istio GW API), AGC, or AGIC.
   - No → any option on the table.

2. **Where do you want the L7 data plane to live?**
   - In the cluster (cheap, flexible, you operate it) → App Routing,
     ingress-nginx, NIC/NGF, Istio, Cilium, Traefik, Kong, HAProxy, Envoy GW.
   - In Azure as a managed service (off-load ops, native WAF) → AGC or AGIC.
   - At the global edge → Front Door (often **in addition to** an in-cluster
     controller, not instead of it).

3. **Gateway API or Ingress v1?**
   - Gateway API (recommended for new work) → App Routing, AGC, NGF,
     Istio, Cilium, Traefik v3, Kong, Envoy GW.
   - Ingress v1 only → ingress-nginx, AGIC, plus most of the above (legacy mode).

4. **WAF required?**
   - Yes, managed → AGC, AGIC (AppGw WAF), Front Door Premium.
   - Yes, in-cluster → NGINX App Protect, HAProxy Enterprise, Kong + plugin,
     or Coraza sidecar on Traefik/Envoy.

5. **Need mTLS / service mesh anyway?**
   - Yes → App Routing (Istio), self-managed Istio, Linkerd + Gateway,
     Cilium mTLS.

---

## Recommendation for this environment

Given the migration this repo automates:

- **Primary**: continue with **App Routing add-on (approuting-istio)**.
  It's Microsoft-supported, Gateway API native, KV-integrated, supports
  public **and** internal LBs (this repo's §7.4), and removes the
  community-NGINX upgrade tax.
- **Add WAF** later by fronting the App Routing public Gateway with
  **Azure Front Door Premium** (global WAF, DDoS) **or** by switching
  internet-facing workloads to **AGC** when they need request-level
  policy enforcement Microsoft will operate for you.
- Keep the internal-LB Gateway from §7.4 for vnet-only traffic — no need
  to put internal apps behind Front Door or AGC.

This gives you a single in-cluster pattern (Gateway + HTTPRoute) regardless
of whether traffic is public or private, and a clean upgrade path if WAF
requirements grow.
