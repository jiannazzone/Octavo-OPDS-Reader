#!/bin/zsh
# Reads the running app's accessibility tree and runs Apple's audit (docs/notes/accessibility.md).
#
#   probe.sh start <udid>        builds the probe if needed and starts it, headless, on that simulator
#   probe.sh dump                the current screen's tree
#   probe.sh audit               Apple's audit of the current screen. Fold the Duo first:
#                                the contrast part measures nothing unfolded.
#   probe.sh tap <label>         taps the first element with that label
#   probe.sh stop
#
# The tree and the audit include elements the app hides with accessibilityHidden,
# so neither shows what VoiceOver skips, and the audit's counts are rough.
setopt null_glob
tools=${0:A:h}
work=${PROBE_WORK:-${TMPDIR:-/tmp}/octavo-a11y-probe}
io=$work/io

case $1 in
start)
    udid=$2
    mkdir -p $io
    rm -f $io/*(N)
    args=(-project $tools/A11yProbe.xcodeproj -scheme Probe -destination "platform=iOS Simulator,id=$udid"
          -derivedDataPath $work/dd -parallel-testing-enabled NO -collect-test-diagnostics never)
    [[ -d $work/dd/Build/Products/Debug-iphonesimulator/Host.app ]] || xcodebuild build-for-testing $args -quiet || exit 1
    TEST_RUNNER_PROBE_IO=$io nohup xcodebuild test-without-building $args > $work/run.log 2>&1 &
    disown
    print "started; log: $work/run.log"
    ;;
stop)
    print -r -- exit > $io/cmd.tmp && mv $io/cmd.tmp $io/cmd.txt
    ;;
*)
    rm -f $io/out-*.txt(N)
    print -r -- "$*" > $io/cmd.tmp && mv $io/cmd.tmp $io/cmd.txt
    for i in {1..600}; do
        replies=($io/out-*.txt(N))
        if (( $#replies )); then
            cat $replies[1]
            rm -f $replies[1]
            exit 0
        fi
        sleep 0.2
    done
    print "no reply"
    exit 1
    ;;
esac
