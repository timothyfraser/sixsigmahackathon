# Hand-checkable known answers (from PR #1, methods §4.2)

KA-1: 10 one-minute observations, bikes = [2,1,0,0,0,1,2,8,10,10], capacity 10, flags TRUE. Rent-unusable = **3**, return-unusable = **2**, either-unusable = **5**; bike early-warning = **4**, dock early-warning = **1**. Known minutes = 10, coverage = 100%.

KA-1b: remove 07:04 snapshot: 3/2/5, known 10. Remove 07:03–07:05: 3 rent-unusable of 9 known, 1 unknown, coverage 90%. Add conflicting 07:02 row: rent-unusable 2, known 10, one conflict. Add 07:05:30 snapshot: no change to 07:05 minute.

KA-2: 5 rent-attempt subgroups of 100 with failures 4,6,5,3,7: total 25/500 = **5%**; p-bar 0.05, LCL 0, UCL 0.115383.

KA-7: three 3-task response subgroups (10,12,14), (11,13,15), (9,12,15) minutes: X-double-bar 12.333, R-bar 4.667. With operator-entered USL 20, Cpu 0.927 if in control and assumptions hold. No USL => no Cpu.

These known-answer fixtures are independent of the large scenario datasets; they are formula acceptance checks, not measured statistics of the simulated scenarios.
