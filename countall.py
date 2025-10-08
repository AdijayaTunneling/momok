#!/usr/bin/env python3
import subprocess, re, json, os

def count_ssh_users():
    # Hitung jumlah akun SSH dari /etc/passwd
    result = subprocess.getoutput("grep -c '/home/' /etc/passwd")
    return int(result.strip())

def count_xray_users(config_path="/etc/xray/config.json"):
    if not os.path.exists(config_path):
        return 0, 0, 0

    with open(config_path, "r") as f:
        raw = f.readlines()

    # Hilangkan baris komentar
    clean_lines = [line for line in raw if not re.match(r'^\s*#', line)]
    clean_json = "".join(clean_lines)
    try:
        data = json.loads(clean_json)
    except json.JSONDecodeError:
        return 0, 0, 0

    vmess_users, vless_users, trojan_users = set(), set(), set()

    if "inbounds" in data:
        for inbound in data["inbounds"]:
            if "settings" in inbound and "clients" in inbound["settings"]:
                proto = inbound.get("protocol", "")
                for client in inbound["settings"]["clients"]:
                    user = client.get("email") or client.get("id") or ""
                    if not user:
                        continue
                    if proto == "vmess":
                        vmess_users.add(user)
                    elif proto == "vless":
                        vless_users.add(user)
                    elif proto == "trojan":
                        trojan_users.add(user)

    return len(vmess_users), len(vless_users), len(trojan_users)

if __name__ == "__main__":
    ssh_count = count_ssh_users()
    vmess_count, vless_count, trojan_count = count_xray_users()
    total = ssh_count + vmess_count + vless_count + trojan_count

    # Output hanya total saja
    print(total)

