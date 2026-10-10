# Fabric source services (EC2 DEV)

A single Docker Compose project, `fabric-source`, runs two independently reachable source services on the **existing** Ubuntu EC2 host:

| Service | Container | EC2 public port | Container port |
|---|---|---:|---:|
| SQL Server 2022 Developer | `fabric-sqlserver` | TCP 1433 | TCP 1433 |
| SFTP (atmoz/sftp) | `fabric-sftp` | TCP 2222 | TCP 22 |

No custom Docker `hostname` is needed. Containers on the same Compose network can resolve the service name `sqlserver`; Fabric uses the EC2 Elastic IP and public-facing port. Host port 22 remains reserved for Ubuntu SSH management.

## Existing DEV instance: adopt without losing databases

The current machine keeps:
- **SQL Server data:** existing named volume `fabric_sqlserver_data` (declared `external: true`; do not delete, format or replace).
- **SFTP data:** `/opt/fabric-sftp/data/outbound` (bind-mounted to the chroot user's `/outbound`).
- **Persistent SFTP host identity:** `/opt/fabric-sftp/hostkeys/ssh_host_ed25519_key*` (do not regenerate when Fabric already trusts the host key).
- **Real credentials:** local `.env`, excluded from Git.

Do **not** re-run migration/removal commands from the historical troubleshooting session on a working instance. This file documents the desired-state artifacts, not an instruction to recreate current containers.

From the EC2 shell, inspect first:

```bash
sudo docker ps
sudo docker volume inspect fabric_sqlserver_data
sudo docker inspect fabric-sqlserver fabric-sftp \
  --format '{{.Name}} project={{index .Config.Labels "com.docker.compose.project"}}'
```

The live combined Compose file was originally placed at `/home/ubuntu/compose.yaml`. To use the versioned Docker Compose artifact as its source of truth, copy **only after comparing** changes with the live file, keeping `/home/ubuntu/.env` unchanged:

```bash
# On EC2, after cloning/pulling this repository:
diff -u /home/ubuntu/compose.yaml infrastructure/source/docker-compose.yaml || true
# If the two configs have been checked and the versioned file is desired:
cp infrastructure/source/docker-compose.yaml /home/ubuntu/compose.yaml
cd /home/ubuntu
sudo docker compose config --quiet
sudo docker compose up -d
sudo docker compose ps
```

Do not run `docker compose down -v`. For databases with important data, take a verified backup before modifying containers or image versions. The floating `2022-latest` tag may change over time; pin an approved image digest for reproducible production-style deployments.

## Fresh host setup

1. Install Docker Engine and Docker Compose Plugin on Ubuntu. Provision an adequately sized EC2 instance and EBS volume; SQL Server's memory cap is 5120 MB, **not** a complete VM-sizing recommendation. Ensure the host has enough RAM for SQL Server, Ubuntu and both containers.
2. Create the named volume before starting Compose: `sudo docker volume create fabric_sqlserver_data`. This project intentionally uses `external: true` to prevent accidental ownership changes between Compose project names.
3. Run `bash infrastructure/source/init-sftp-host.sh` on EC2 (from the cloned repository). This prepares directories, ownership and a persistent ED25519 server host key. Re-running it preserves an existing host key.
4. Copy `infrastructure/source/.env.example` to `/home/ubuntu/.env`; replace placeholder values with strong secrets. An existing instance must reuse its current `MSSQL_SA_PASSWORD` and `SFTP_PASSWORD`. Secure it with `chmod 600 /home/ubuntu/.env`. If the original SFTP password was generated earlier, it may still be in `/opt/fabric-sftp/.env`; never print or commit it in logs.
5. Place `compose.yaml` at `/home/ubuntu/compose.yaml`, then start:
   ```bash
   cd /home/ubuntu
   sudo docker compose config --quiet
   sudo docker compose up -d
   sudo docker compose ps
   ```

The `atmoz/sftp` entrypoint creates user `sftp_logistics_vendor` (UID/GID 1001) from the Compose `command`. No separate Ubuntu user is required. Confirm with `sudo docker exec fabric-sftp id sftp_logistics_vendor`.

## Upload demo CSVs

The tracked sample fixtures are in `scripts/source/sftp/outbound/inventory/`. From the **Mac repository root**, upload using the existing EC2 management SSH key and port 22 (restricted to your current public IP):

```bash
scp -i /path/to/your-key.pem -r \
  scripts/source/sftp/outbound/inventory \
  ubuntu@<EC2_ELASTIC_IP>:/home/ubuntu/
```

Then, **on EC2**:

```bash
sudo cp -r /home/ubuntu/inventory/. /opt/fabric-sftp/data/outbound/inventory/
sudo chown -R 1001:1001 /opt/fabric-sftp/data/outbound
sudo find /opt/fabric-sftp/data/outbound -type f
```

The copy is required only because the example SCP command stages files in `/home/ubuntu/inventory`. SFTP serves the bind-mounted host directory at remote `/outbound/inventory/`, so direct SFTP uploads to that location would eliminate the extra host-side copy.

The `inventory_snapshot.csv` fixture sits under `/outbound/inventory/`; movement CSVs retain their `movements/YYYY/MM/` directories. Existing ingestion metadata uses `/outbound/inventory/` and `/outbound/inventory/movements/`. For incremental file ingestion, the framework uses the **remote file LastModifiedTime**, not the filename timestamp. Uploading can change that value.

## AWS firewall / Microsoft Fabric Connections

Keep EC2's Security Group restricted by source CIDRs, protocol and port. In this DEV environment, the SQL Server Fabric Cloud Connection passed after allowing the IPv4 ranges of `PowerBI.SoutheastAsia` on TCP **1433**. That is an observed result, **not** a guarantee that all Fabric connectors use the same source IPs. Test SFTP on TCP **2222** separately. If using the same CIDRs, configure a distinct 2222 ingress rule for each applicable range. Maintain the allowlist from the authoritative current Microsoft Service Tags publication; ranges may change. Avoid `0.0.0.0/0` on SQL Server or SFTP.

Fabric Connection registration:

| Logical connection_ref | Fabric connection | Host/port | Authentication |
|---|---|---|---|
| `SQL_SERVER_ECOMMERCE` | `cn_sql_server_ecommerce` | Elastic IP:1433, DB `sql_ecommerce_db` | SQL Basic |
| `SQL_SERVER_BENCHMARK` | `cn_src_sql_server_benchmark_db` | Elastic IP:1433, DB `sql_benchmark_db` | SQL Basic |
| `SFTP_LOGISTICS_VENDOR` | `cn_sftp_logistics_vendor` | Elastic IP:2222 | SFTP Basic |

For the SFTP host key fingerprint **on EC2**:

```bash
sudo ssh-keygen -E md5 -lf /opt/fabric-sftp/hostkeys/ssh_host_ed25519_key.pub
```

Use the host-key format required by the Fabric connector UI; the fingerprint authenticates the **server**, whereas Basic credentials authenticate the **client**. Fetch the SFTP password from `/home/ubuntu/.env` privately; never include it in issues, screenshots or Git. The EC2 SSH `.pem` key is unrelated to the SFTP login.

After creating and testing each Fabric Connection, register the **Fabric connection IDs** in `scripts/control/03_seed_connection_settings.sql` for the relevant environment. Existing Control Databases should be updated non-destructively: preserve Watermarks, Audit History and existing ingestion config IDs. Do not commit environment-specific IDs or passwords.

## Checks and safety

```bash
sudo docker compose -f /home/ubuntu/compose.yaml ps
sudo docker inspect fabric-sqlserver --format '{{range .Mounts}}{{println .Name .Destination}}{{end}}'
sudo docker logs --tail 30 fabric-sftp
```

Expected SQL Server mount: `fabric_sqlserver_data /var/opt/mssql`. Verify `sql_ecommerce_db` and `sql_benchmark_db` from DBeaver after any migration. The SFTP host-key private file, real `.env`, SQL Server database files and any user-uploaded data must never be checked into Git.
