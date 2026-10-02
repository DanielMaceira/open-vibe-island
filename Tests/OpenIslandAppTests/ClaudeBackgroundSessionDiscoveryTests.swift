import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct ClaudeBackgroundSessionDiscoveryTests {
    /// `claude agents --cwd .` dispatches sessions to the Claude Code daemon.
    /// Only the daemon-hosted engine is a session; the agents view, the daemon,
    /// its pty hosts and warm spares must not surface as phantom sessions.
    @Test
    func discoverReportsDaemonHostedEngineBySessionIDAndSkipsControlProcesses() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  100 1 ?? /Applications/iTerm.app/Contents/MacOS/iTerm2
                  110 100 ttys000 -zsh
                  120 110 ttys000 claude agents --cwd . --dangerously-skip-permissions
                  130 1 ?? /Users/test/.local/bin/claude daemon run --origin transient
                  140 130 ?? /Users/test/.local/share/claude/ClaudeCode.app/Contents/MacOS/claude --bg-pty-host /tmp/cc-daemon-501/x/pty/72e15398.sock 207 58 -- /Users/test/.local/share/claude/versions/2.1.287
                  150 140 ttys002 /Users/test/.local/share/claude/versions/2.1.287 --session-id 72e15398-ff3d-4a74-9d70-2424686dccdc --agent claude --permission-mode bypassPermissions
                  160 130 ?? claude bg-pty-host --bg-pty-host /tmp/cc-daemon-501/x/spare/a.pty.sock 200 50 -- /Users/test/.local/share/claude/versions/2.1.287 --bg-spare /tmp/cc-daemon-501/x/spare/a.claim.sock
                  170 160 ttys001 claude bg-spare --bg-spare /tmp/cc-daemon-501/x/spare/a.claim.sock
                  180 110 ttys003 claude attach 72e15398
                """
            }

            guard executablePath == "/usr/sbin/lsof",
                  let pid = arguments.dropFirst(2).first else {
                return nil
            }

            switch pid {
            case "150":
                return """
                fcwd
                n/Users/test/dev/local
                n/Users/test/.claude/projects/-Users-test-dev-local/72e15398-ff3d-4a74-9d70-2424686dccdc.jsonl
                """
            default:
                Issue.record("unexpected lsof lookup for pid \(pid)")
                return nil
            }
        }

        let snapshots = discovery.discover()

        #expect(snapshots == [
            .init(
                tool: .claudeCode,
                sessionID: "72e15398-ff3d-4a74-9d70-2424686dccdc",
                workingDirectory: "/Users/test/dev/local",
                terminalTTY: nil,
                transcriptPath: "/Users/test/.claude/projects/-Users-test-dev-local/72e15398-ff3d-4a74-9d70-2424686dccdc.jsonl"
            ),
        ])
    }

    @Test
    func interactiveClaudeInTerminalTabIsStillDiscovered() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  100 1 ?? /Applications/iTerm.app/Contents/MacOS/iTerm2
                  110 100 ttys000 -zsh
                  120 110 ttys000 claude --name feature-x
                """
            }

            guard executablePath == "/usr/sbin/lsof", arguments.dropFirst(2).first == "120" else {
                return nil
            }
            return """
            fcwd
            n/Users/test/dev/local
            """
        }

        let snapshots = discovery.discover()

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.workingDirectory == "/Users/test/dev/local")
        #expect(snapshots.first?.terminalTTY == "/dev/ttys000")
    }
}
