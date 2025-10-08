<?php
// Debug maksimal
error_reporting(E_ALL);
ini_set('display_errors', 1);

header('Content-Type: application/json');

// Ambil action dari GET
$action  = $_GET['action'] ?? '';
// Ambil payload dari body (POST JSON)
$payload = json_decode(file_get_contents("php://input"), true) ?? [];

// Helper shell
function run_cmd($cmd) {
    $out = shell_exec($cmd . " 2>&1");
    return trim($out ?? '');
}

// ============ SWITCH =============
switch ($action) {

    case "countall":
        $output = run_cmd("/usr/bin/python3 /usr/local/sbin/countall.py");
        if (is_numeric($output)) {
            echo json_encode(["status" => "ok", "total" => (int)$output]);
        } else {
            echo json_encode(["status" => "error", "msg" => $output]);
        }
        break;

    case "trialssh":
        $out = run_cmd("sudo -n /usr/local/sbin/trialsshbot");
        if ($out === "") {
            echo json_encode(["status" => "error", "msg" => "trialssh failed"]);
        } else {
            // Pisahkan output berdasarkan tag
            $output1 = '';
            $output2 = '';
            if (strpos($out, "===OUTPUT1===") !== false && strpos($out, "===OUTPUT2===") !== false) {
                $parts = explode("===OUTPUT2===", $out, 2);
                $output1 = trim(str_replace("===OUTPUT1===", "", $parts[0]));
                $output2 = trim($parts[1]);
            } else {
                $output1 = trim($out);
            }

            echo json_encode([
                "status"  => "ok",
                "output1" => $output1,
                "output2" => $output2
            ]);
        }
        break;

    case "trialvmess":
        $out = run_cmd("sudo -n /usr/local/sbin/trialwsbot");
        if ($out === "") {
            echo json_encode(["status" => "error", "msg" => "trialvmess failed"]);
        } else {
            // Pisahkan output berdasarkan tag
            $output1 = '';
            $output2 = '';
            if (strpos($out, "===OUTPUT1===") !== false && strpos($out, "===OUTPUT2===") !== false) {
                $parts = explode("===OUTPUT2===", $out, 2);
                $output1 = trim(str_replace("===OUTPUT1===", "", $parts[0]));
                $output2 = trim($parts[1]);
            } else {
                $output1 = trim($out);
            }

            echo json_encode([
                "status"  => "ok",
                "output1" => $output1,
                "output2" => $output2
            ]);
        }
        break;

    case "addssh":
        $username = $payload['username'] ?? '';
        $password = $payload['password'] ?? '';
        $iplimit  = $payload['iplimit'] ?? '1';
        $exp      = $payload['exp'] ?? '1';

        if (!$username || !$password) {
            echo json_encode(["status" => "error", "msg" => "Username & Password wajib"]);
            exit;
        }

        $cmd = sprintf(
            "sudo -n /usr/local/sbin/addsshbot %s %s %s %s",
            escapeshellarg($username),
            escapeshellarg($password),
            escapeshellarg($iplimit),
            escapeshellarg($exp)
        );
        $out = run_cmd($cmd);

        // Pisahkan output berdasarkan tag ===OUTPUT1=== dan ===OUTPUT2===
        $output1 = '';
        $output2 = '';
        if (strpos($out, "===OUTPUT1===") !== false && strpos($out, "===OUTPUT2===") !== false) {
            $parts = explode("===OUTPUT2===", $out, 2);
            $output1 = trim(str_replace("===OUTPUT1===", "", $parts[0]));
            $output2 = trim($parts[1]);
        } else {
            $output1 = trim($out);
        }

        echo json_encode([
            "status"  => "ok",
            "output1" => $output1,
            "output2" => $output2
        ]);
        break;

    case "addvmess":
        $username = $payload['username'] ?? '';
        $quota    = $payload['gb'] ?? '0';
        $iplimit  = $payload['iplimit'] ?? '1';
        $exp      = $payload['exp'] ?? '1';

        if (!$username) {
            echo json_encode(["status" => "error", "msg" => "Username wajib"]);
            exit;
        }

        $cmd = sprintf(
            "sudo -n /usr/local/sbin/addwsbot %s %s %s %s",
            escapeshellarg($username),
            escapeshellarg($quota),
            escapeshellarg($iplimit),
            escapeshellarg($exp)
        );
        $out = run_cmd($cmd);

        // Pisahkan output berdasarkan tag ===OUTPUT1=== dan ===OUTPUT2===
        $output1 = '';
        $output2 = '';
        if (strpos($out, "===OUTPUT1===") !== false && strpos($out, "===OUTPUT2===") !== false) {
            $parts = explode("===OUTPUT2===", $out, 2);
            $output1 = trim(str_replace("===OUTPUT1===", "", $parts[0]));
            $output2 = trim($parts[1]);
        } else {
            $output1 = trim($out);
        }

        echo json_encode([
            "status"  => "ok",
            "output1" => $output1,
            "output2" => $output2
        ]);
        break;

    default:
        echo json_encode(["status" => "error", "msg" => "invalid action"]);
}
?>

