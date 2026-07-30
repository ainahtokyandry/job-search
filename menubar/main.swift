// JobSearchBar — the job search section on its own, as its own menu bar app.
//
// The section itself is in JobSearchSection.swift, and it is the same file MacBar compiles
// in when it puts several sections behind one menu bar item. This entry point
// exists so the indicator can be run without MacBar.

import AppKit

Host.run(sections: [JobSearchSection()])
