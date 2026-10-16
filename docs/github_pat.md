# Getting Your Github Personal Access Token to Commit, Pull, and Push to Repos

Estimated Time: 10 minutes

In this activity, you are asked to follow the necessary steps to allow you to commit, pull, and push changes on GitHub repositories. Please be sure to create a GitHub Repository first.

## Prerequisites 
- Must have already made a GitHub Account
- Must have already made or been added to a GitHub Repository 
- Must have the complete URL of the GitHub Repository. For example, our GitHub Repository is https://GitHub.com/timothyfraser/sixsigmahackathon.git


## Tasks
- Navigate to GitHub.com and click on your profile icon in the upper right hand corner. 
- Click on Profile
- In the left hand menu, navigate to Developer Settings
- Select Create a Personal Access Token. You can either make a fine-grained token, where you specify the repository that this token will grant you access to, or a standard token, which will grant the bearer access to all your GitHub repositories. Either is fine, but I recommend a standard token for new users.
- Create a name for the token 
- Create an expiration date for the token. Pick one after the end of this term.
- Under scopes, you are asked to select what powers to give to this token - EG what functions do you allow a user who bears your token to perform? Please select the public_repo scope and repo scope.
- Copy the token, and store it in a secure location. Some people put them in their password manager app; others put them in a note-taking app.
- Open up Posit Cloud / RStudio / Positron / Cursor / VSCode
- Create a new project from GitHub, using your repositories GitHub URL. Should end in .git
- Install these two packages: `install.packages(c("gert", "credentials"))`
- Create one new file.
- Run the following script below, and then look at the output of your R console and terminal.

```r
library(gert)

library(credentials)

credentials::set_github_pat()

# this will prompt a popup that asks you to enter your GitHub Personal Access Token.

gert::git_pull() # pull most recent changes from GitHub

gert::git_add(dir(all.files = TRUE)) # select any and all new files created or edited to be 'staged'

# 'staged' files are to be saved anew on GitHub 

gert::git_commit_all("my first commit") # save your record of file edits - called a commit

gert::git_push() # push your commit to GitHub
```

