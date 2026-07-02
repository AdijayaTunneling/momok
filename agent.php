<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

header('Content-Type: application/json');

$action  = $_GET['action'] ?? '';
$payload = json_decode(file_get_contents("php://input"), true) ?? [];

function run_cmd($cmd) {
    $out = shell_exec($cmd . " 2>&1");
    return trim($out ?? '');
}

function parse_bot_output($out) {

    if ($out === "") {
        return [
            "status" => "error",
            "msg" => "backend empty response"
        ];
    }

    if (
        stripos($out, "ERROR") !== false ||
        stripos($out, "failed") !== false ||
        stripos($out, "invalid") !== false
    ) {
        return [
            "status" => "error",
            "msg" => $out
        ];
    }

    $output1 = '';
    $output2 = '';

    if (
        strpos($out, "===OUTPUT1===") !== false &&
        strpos($out, "===OUTPUT2===") !== false
    ) {
        $parts = explode("===OUTPUT2===", $out, 2);
        $output1 = trim(str_replace("===OUTPUT1===", "", $parts[0]));
        $output2 = trim($parts[1]);
    } else {
        $output1 = trim($out);
    }

    return [
        "status"  => "ok",
        "output1" => $output1,
        "output2" => $output2
    ];
}

switch ($action) {

    case "countall":
        $output = run_cmd("/usr/bin/python3 /usr/local/sbin/countall.py");

        if (is_numeric($output)) {
            echo json_encode([
                "status" => "ok",
                "total" => (int)$output
            ]);
        } else {
            echo json_encode([
                "status" => "error",
                "msg" => $output
            ]);
        }
        break;

    case "trialssh":
        echo json_encode(
            parse_bot_output(
                run_cmd("sudo -n /usr/local/sbin/trialsshbot")
            )
        );
        break;

    case "trialvmess":
        echo json_encode(
            parse_bot_output(
                run_cmd("sudo -n /usr/local/sbin/trialwsbot")
            )
        );
        break;

    case "addssh":

        $username = $payload['username'] ?? '';
        $password = $payload['password'] ?? '';
        $iplimit  = $payload['iplimit'] ?? '1';
        $exp      = $payload['exp'] ?? '1';

        if (!$username || !$password) {
            echo json_encode([
                "status" => "error",
                "msg" => "Username & Password wajib"
            ]);
            exit;
        }

        $cmd = sprintf(
            "sudo -n /usr/local/sbin/addsshbot %s %s %s %s",
            escapeshellarg($username),
            escapeshellarg($password),
            escapeshellarg($iplimit),
            escapeshellarg($exp)
        );

        echo json_encode(
            parse_bot_output(
                run_cmd($cmd)
            )
        );

        break;

    case "addvmess":

        $username = $payload['username'] ?? '';
        $quota    = $payload['gb'] ?? '0';
        $iplimit  = $payload['iplimit'] ?? '1';
        $exp      = $payload['exp'] ?? '1';

        if (!$username) {
            echo json_encode([
                "status" => "error",
                "msg" => "Username wajib"
            ]);
            exit;
        }

        $cmd = sprintf(
            "sudo -n /usr/local/sbin/addwsbot %s %s %s %s",
            escapeshellarg($username),
            escapeshellarg($quota),
            escapeshellarg($iplimit),
            escapeshellarg($exp)
        );

        echo json_encode(
            parse_bot_output(
                run_cmd($cmd)
            )
        );

        break;

    case "addvless":

        $username = $payload['username'] ?? '';
        $quota    = $payload['gb'] ?? '0';
        $iplimit  = $payload['iplimit'] ?? '1';
        $exp      = $payload['exp'] ?? '1';

        if (!$username) {
            echo json_encode([
                "status" => "error",
                "msg" => "Username wajib"
            ]);
            exit;
        }

        $cmd = sprintf(
            "sudo -n /usr/local/sbin/addvlessbot %s %s %s %s",
            escapeshellarg($username),
            escapeshellarg($quota),
            escapeshellarg($iplimit),
            escapeshellarg($exp)
        );

        echo json_encode(
            parse_bot_output(
                run_cmd($cmd)
            )
        );

        break;

    case "addtrojan":

        $username = $payload['username'] ?? '';
        $quota    = $payload['gb'] ?? '0';
        $iplimit  = $payload['iplimit'] ?? '1';
        $exp      = $payload['exp'] ?? '1';

        if (!$username) {
            echo json_encode([
                "status" => "error",
                "msg" => "Username wajib"
            ]);
            exit;
        }

        $cmd = sprintf(
            "sudo -n /usr/local/sbin/addtrbot %s %s %s %s",
            escapeshellarg($username),
            escapeshellarg($quota),
            escapeshellarg($iplimit),
            escapeshellarg($exp)
        );

        echo json_encode(
            parse_bot_output(
                run_cmd($cmd)
            )
        );

        break;

    case "ceklogin":
        $username = $payload['username'] ?? '';
        $protocol = $payload['protocol'] ?? '';

        if (!$username || !$protocol) {
            echo json_encode([
                "status" => "error",
                "msg" => "Username & Protocol wajib"
            ]);
            exit;
        }

        $cmd = sprintf(
            "sudo -n /usr/local/sbin/cekloginbot %s %s",
            escapeshellarg($username),
            escapeshellarg($protocol)
        );

        $out = run_cmd($cmd);
        $result = json_decode($out, true);
        if ($result && isset($result['status'])) {
            echo json_encode($result);
        } else {
            echo json_encode([
                "status" => "error",
                "msg" => "Gagal memproses cek login: " . $out
            ]);
        }
        break;

    default:
        echo json_encode([
            "status" => "error",
            "msg" => "invalid action"
        ]);
}
?>
