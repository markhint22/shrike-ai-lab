#!/usr/bin/env python3
"""make_xmltv.py - generate the multi-channel QA guide fixture (stdlib only).

The canonical staging guide feed has 1 channel / 1 program, so guide-channel-picker (needs >=2 mapped channels) and
guide-program-loadmore (needs a long schedule) cannot pass. Host the output at any public URL (e.g. as another file in the existing
QA fixture gist), then export DL_GUIDE_MULTI_URL=<raw url> for run_nightly.sh: seed_data.py adds it as a guide source and auto-maps it,
the janitor removes it after the run, and the two specs leave known_issues.json automatically.

  make_xmltv.py > qa-test-guide-multi.xml          (channel names match the staging streams so auto-map pairs them)
"""
import datetime
import sys
from xml.sax.saxutils import escape

CHANNELS = [("qa.test.channel", "QA Test Channel 1"), ("qa.test.channel2", "QA Test Channel 2"), ("qa.test.channel3", "Mux Live Test")]
PROGRAMS_PER_CHANNEL = 672  # 30 min slots = 14 days (static hosting goes stale, so keep the window wide)


def main():
    start = datetime.datetime.now(datetime.timezone.utc).replace(minute=0, second=0, microsecond=0) - datetime.timedelta(hours=24)
    f = "%Y%m%d%H%M%S +0000"
    out = ['<?xml version="1.0" encoding="UTF-8"?>', '<tv generator-info-name="qa-devicelane">']
    for cid, name in CHANNELS:
        out.append('<channel id="%s"><display-name>%s</display-name></channel>' % (cid, escape(name)))
    for cid, name in CHANNELS:
        for i in range(PROGRAMS_PER_CHANNEL):
            a = start + datetime.timedelta(minutes=30 * i)
            b = a + datetime.timedelta(minutes=30)
            out.append('<programme start="%s" stop="%s" channel="%s"><title>%s Program %d</title><desc>QA fixture</desc></programme>'
                       % (a.strftime(f), b.strftime(f), cid, escape(name), i + 1))
    out.append("</tv>")
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
