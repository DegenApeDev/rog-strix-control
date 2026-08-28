# Security

ROG Strix Control Deck runs unsandboxed as the current user. It never requires
root access, evaluates user input as shell code, or starts another Quickshell
process. Hardware-changing commands are allowlisted, validated, serialized,
and preset transactions attempt rollback on failure.

The optional CPU-watts setup uses fixed absolute executables and paths through
`pkexec`; it never invokes a privileged shell. Its udev rule grants read-only
`0440` access to `wheel`, never world or write access, and can be removed from
the same UI. RAPL access remains opt-in because fine-grained energy counters
can increase local side-channel exposure.

Report security issues privately to the repository owner before public
disclosure. Include the plugin version, affected action, sanitized diagnostic
report, and reproduction steps. Do not include serial numbers or account data.
