# Production HA Design

From single-node ECS deployment into a production-ready highly available architecture for the same PHP, MySQL, and Redis stack.

## Managed AWS Approach

For production, I would prefer managed services for the stateful tiers. They reduce operational risk, shorten recovery time, and let the team focus on application behavior rather than database orchestration.

### MySQL

Use Amazon RDS for MySQL Multi-AZ or Amazon Aurora MySQL.

- Run the database across multiple Availability Zones with synchronous standby replication for RDS Multi-AZ, or Aurora's distributed storage layer.
- Use automated backups, point-in-time recovery, encryption at rest, and CloudWatch alarms for CPU, memory, connections, replication lag, and storage.
- Use the stable writer endpoint for application writes. Add reader endpoints only if the application gains read-heavy paths that can tolerate replica lag.
- Enable automated failover. During an AZ or instance failure, AWS promotes a healthy standby or replica and keeps the writer endpoint stable.

The application should treat MySQL disconnects as transient. It should use short connection timeouts, retry failed connection attempts with exponential backoff, and reconnect on each request or detect and replace stale pooled connections.

### Redis

Use Amazon ElastiCache for Redis with a replication group, Multi-AZ enabled, and automatic failover.

- Run one primary and at least one replica in different Availability Zones.
- Use the primary endpoint for writes and, where useful, reader endpoints for read-only traffic.
- Enable automatic failover so ElastiCache promotes a replica when the primary fails.
- Configure Redis persistence according to business need. If Redis is only a cache or approximate counter, data loss may be acceptable. If Redis is a source of truth, use durable persistence and clear recovery objectives.

The PHP application should reconnect to Redis after socket errors, use short command timeouts, and avoid assuming every Redis write is durable unless the Redis persistence and replication policy explicitly guarantees that behavior.

## Self-Hosted Approach

Self-hosting is possible, but it increases operational burden. I would choose it only when managed services are unavailable, too costly for a specific workload, or blocked by regulatory or portability constraints.

### MySQL

Run MySQL on dedicated EC2 instances or a container platform with persistent storage, not ephemeral Fargate filesystems.

- Use primary/replica replication or MySQL Group Replication across Availability Zones.
- Store data on durable encrypted EBS volumes with regular snapshots and tested restore procedures.
- Use Orchestrator, ProxySQL, HAProxy, or a similar control plane to detect primary failure, promote a replica, and route traffic to the new writer.
- Monitor replication lag, disk space, backup success, query latency, and failover events.

Failover needs fencing to prevent split-brain writes. The application should connect through a proxy or stable DNS name rather than directly pinning to an instance address.

### Redis

Run Redis with either Sentinel or Redis Cluster.

- Redis Sentinel: one primary, replicas in other Availability Zones, and at least three Sentinel nodes for quorum-based failover.
- Redis Cluster: multiple shards with replicas when horizontal scale and partitioned data are required.
- Use persistent disks and Redis AOF or RDB snapshots if data must survive node loss.
- Put clients behind a stable endpoint or make sure the client library supports Sentinel or Cluster topology updates.

The application must handle `MOVED`, `ASK`, reconnects, and brief write failures if Redis Cluster is used. With Sentinel, the client or proxy must discover the promoted primary after failover.

## Application Changes for Failover

The current app receives static host and credential environment variables. That is enough when endpoints remain stable, but production failover still causes brief connection drops.

Recommended changes:

- Use short MySQL and Redis connect/read timeouts.
- Retry transient connection failures with bounded exponential backoff.
- Recreate failed connections instead of reusing stale sockets indefinitely.
- Make visit logging idempotent enough that a retry does not corrupt counters or duplicate irreversible side effects.
- Surface degraded dependency status in logs and metrics.
- Avoid long-lived transactions for simple visit writes.

## Tradeoffs

Managed services provide the best default production posture: automated failover, backups, patching workflows, observability integrations, and tested recovery paths. The main tradeoffs are cloud lock-in, service limits, and higher direct service cost.

Self-hosted databases offer more control over topology, versions, extensions, and portability. The tradeoff is that the team owns failover automation, backups, patching, recovery testing, monitoring, capacity planning, and incident response. For this stack, I would use managed RDS or Aurora for MySQL and ElastiCache for Redis unless there is a strong constraint against managed services.
