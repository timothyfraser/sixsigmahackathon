![](images/banner_thin.png)
---

# 🗨️ Prompts

> **Prompts are revealed at kickoff on [Devpost](https://six-sigma-hackathon.devpost.com/).**
>
> Devpost is the one place the prompts live. Each track (on-campus and Virtual DL)
> has its own prompts: your team picks **one** from your track, puts its number and
> title in [`SPEC.md`](../SPEC.md), and designs a tool around it.

---

### 💡 The Challenge

Over 24 hours, your team tackles a real-world quality control and reliability
problem. Prompts are solution-neutral on purpose — many different tools can
address the same prompt well.

**The statistics are the graded core.** Statistical process control, process
capability, reliability modeling, failure analysis: that is what is scored. The
app you build is the delivery vehicle for the analysis, not the point.

### ⚙️ Requirements

1. 🚀 **What you ship** — a publicly available tool, formatted as:
   - a dashboard or web app (React Vite front end)
   - a statistical tool, formatted as either:
      - an R package or Python library, AND/OR
      - a public REST API (FastAPI in Python, or plumber in R)
2. 📈 **2-3 test datasets** demonstrating the tool. They need not be real data,
   but they should look like what the data would look like in the field.
3. 📑 **A codebook and README** for your datasets — what each file and variable
   means, and what it would take to collect this data for real.
4. 🐙 **Everything public and reproducible** on GitHub.

### 🔧 Example Techniques

- Statistical Process Control (SPC) — X-bar/R, I-MR, p, c charts
- Process capability (Cp, Cpk)
- Mean Time to Failure (MTTF) and probability of failure
- System reliability modeling (series, parallel, k-out-of-n)
- Fault tree analysis

### 👍 Advice

- This project is short. Define scope early so you finish.
- A small product that works beats a big one that doesn't.
- Verify your statistics against a case whose answer you already know **before**
  you style anything — see
  [`stats-first-steering`](../.claude/skills/stats-first-steering/SKILL.md).
- Your team has multiple members. Delegate and specialize.

### 📚 More

- 🔢 [Evaluation Criteria](criteria.md)
- 📚 [Resources for Building Your Tool](resources.md)
- [🏠 Homepage](https://github.com/timothyfraser/sixsigmahackathon/tree/main)

---

![](images/banner_icons.png)

<p align="center">
  <b><a href="https://github.com/timothyfraser/sixsigmahackathon/tree/main">🏠 Return to Home Page</a></b>
</p>
