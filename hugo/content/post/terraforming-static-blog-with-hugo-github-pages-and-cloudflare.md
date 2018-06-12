---
title: "Terraforming a static blog with Hugo, GitHub Pages, and Cloudflare"
date: 2018-06-10T19:39:22-07:00
draft: false
categories:
- hugo
- cloudflare
- terraform
- github-pages
- disqus
---

Hello, world! This is my first blog post (on my own site, [anyway](https://blog.cloudflare.com/author/patrick/)). Had I started this site a few years ago I would have used something like Medium, but because this is 2018 I decided to see what the buzz about [statically generated sites](https://gohugo.io/about/benefits/) was all about. We use [Hugo](https://gohugo.io/) at Cloudflare for our https://developers.cloudflare.com site and it was both fun and easy to use while writing the [Cloudflare Terraform tutorial](https://developers.cloudflare.com/terraform/tutorial/hello-world/), so that's what I went with for my personal blog.

Fittingly, this first post is all about setting up a statically generated site using Hugo, hosting it on [GitHub Pages](https://pages.github.com/), and serving it at the edge with [Cloudflare](https://www.cloudflare.com). I use Terraform to manage both Cloudflare and GitHub, and my configuration files can be found in [this repository](https://github.com/prdonahuedotcom/blog). Other notes I took as I went are interspersed as well, in case anyone finds them helpful.

<!--more-->

## Prerequisites

Before getting started, you'll need to install a couple tools (Hugo and Terraform) and set up a couple accounts (GitHub and Cloudflare).

### i. Hugo

The easiest way to install Hugo on macOS is through Homebrew:

```
$ brew install hugo
...
$ hugo version
Hugo Static Site Generator v0.41 darwin/amd64
```

### ii. Terraform

You will need Terraform installed. See [these instructions](https://developers.cloudflare.com/terraform/getting-started/installing/) for an overview.

On a Mac, this is easy with Homebrew:

```
$ brew install terraform

==> Downloading https://homebrew.bintray.com/bottles/terraform-0.11.6.sierra.bottle.tar.gz
######################################################################## 100.0%
==> Pouring terraform-0.11.6.sierra.bottle.tar.gz
🍺  /usr/local/Cellar/terraform/0.11.6: 6 files, 80.2MB

$ terraform version
Terraform v0.11.6
```

### iii. Cloudflare

You will need a [Cloudflare account](https://dash.cloudflare.com/sign-up) with your zone added to it.

In an upcoming version of the [Cloudflare Terraform Provider](https://github.com/terraform-providers/terraform-provider-cloudflare), you'll be able to automate zone creation with Terraform, but for now you can add it through the UI.

Note that you do not need to perform any configuration in Cloudflare other than completing zone activation by updating your authoritative nameservers at your registrar. Specifically, you should _not_ add a CNAME yet to GitHub—we'll take care of that below.

### iv. GitHub

You will need a GitHub account and organization, and [personal access token](https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line/) that Terraform can use to authenticate to your repo. The repo itself will be created and managed by Terraform, so you should not create it yet.

Note that unfortunately GitHub built their Terraform provider [to only work with organizations](https://github.com/terraform-providers/terraform-provider-github/issues/45), so you will need to [create an organization](https://help.github.com/articles/creating-a-new-organization-from-scratch/) to host your blog repository.

### v. Disqus (optional)

If you'd like to use Disqus to manage your comments, you should [create an account](https://disqus.com/admin/create/).

When asked "Which platform is your site on?" be sure to click "I don't see my platform listed, install manually with Universal Code". You won't need to copy any of the JavaScript that Disqus provides—your Hugo theme will handle that for you.

Be sure to jot down the "slug" that was generated for you as this will be needed later. My Disqus hostname is prdblog.disqus.com so "prdblog" is what I'll need later.

## Terraform your infrastructure

With the prerequisites out of the way, it's time to have Terraform provision your GitHub repository and Cloudflare zone.

### i. Build the configuration

Replace the environment variables below with your details and then run the provided steps to generate your Terraform configuration.

```
$ export PUBLIC_ZONE="prdonahue.com"
$ export PUBLIC_HOST="blog"
$ export PUBLIC_FQDN="$PUBLIC_HOST.$PUBLIC_ZONE"
$ export GITHUB_ORG="prdonahuedotcom"
$ export REPO_NAME="blog"
$ export REPO_AND_BLOG_DESC="Patrick R. Donahue's Blog"

$ mkdir -p ~/src/$PUBLIC_ZONE/$PUBLIC_HOST && cd $_

$ cat <<EOF | tee variables.tf
## GITHUB
variable "github_organization" {
    default = "$GITHUB_ORG"
}
variable "github_repo" {
    default = "$REPO_NAME"
}
variable "github_repo_desc" {
    default = "$REPO_AND_BLOG_DESC"
}

## CLOUDFLARE
variable "domain" {
    default = "$PUBLIC_ZONE"
}
variable "hostname" {
    default = "$PUBLIC_FQDN"
}
EOF

$ cat <<'EOF' | tee main.tf
## GITHUB
provider "github" {
  # token and organization will be read from $GITHUB_USER and $GITHUB_TOKEN, respectively
  organization = "${var.github_organization}"
}

resource "github_repository" "blog" {
  name        = "${var.github_repo}"
  description = "${var.github_repo_desc}"

  private = false
}

## CLOUDFLARE
provider "cloudflare" {
  # email and token will be read from $CLOUDFLARE_EMAIL and $CLOUDFLARE_TOKEN, respectively
}

resource "cloudflare_zone_settings_override" "zone-settings" {
  name = "${var.domain}"

  settings {
    tls_1_3                  = "on"
    automatic_https_rewrites = "on"
    ssl                      = "strict"
  }
}

resource "cloudflare_record" "blog" {
  domain = "${var.domain}"

  name  = "${var.hostname}"
  type  = "CNAME"
  value = "${var.github_organization}.github.io"

  proxied = "true"
}

# alias the apex and www record to blog
resource "cloudflare_record" "apex" {
  domain = "${var.domain}"

  name  = "${var.domain}"
  type  = "CNAME"
  value = "${var.hostname}"

  proxied = "true"
}

resource "cloudflare_page_rule" "redirect-apex" {
  zone   = "${var.domain}"
  target = "${var.domain}"

  actions = {
    forwarding_url {
      url         = "https://${var.hostname}"
      status_code = 301
    }
  }
}

resource "cloudflare_record" "www" {
  domain = "${var.domain}"

  name  = "www.${var.domain}"
  type  = "CNAME"
  value = "${var.hostname}"

  proxied = "true"
}

resource "cloudflare_page_rule" "redirect-www" {
  zone   = "${var.domain}"
  target = "www.${var.domain}"

  actions = {
    forwarding_url {
      url         = "https://${var.hostname}"
      status_code = 301
    }
  }
}
EOF
```

### ii. Apply the configuration

With the configuration and variable files created, it's time to ask Terraform to adjust our infrastructure to match the desired end-state. Before doing so you'll need to provide your GitHub and Cloudflare credentials in environment variables as shown below. Technically, you can set these in the Terraform config file itself but doing so is a bad security practice.

```bash
$ export GITHUB_USER=your-github-user
$ export GITHUB_TOKEN=your-github-token

$ export CLOUDFLARE_EMAIL=you@example.com
$ export CLOUDFLARE_TOKEN=your-cf-api-key

$ terraform init -upgrade

Initializing provider plugins...
- Checking for available provider plugins on https://releases.hashicorp.com...
- Downloading plugin for provider "github" (1.1.0)...
- Downloading plugin for provider "cloudflare" (1.0.0)...

The following providers do not have any version constraints in configuration,
so the latest version was installed.

To prevent automatic upgrades to new major versions that may contain breaking
changes, it is recommended to add version = "..." constraints to the
corresponding provider blocks in configuration, with the constraint strings
suggested below.

* provider.cloudflare: version = "~> 1.0"
* provider.github: version = "~> 1.1"

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.

$ terraform plan | grep -v "<computed>"
Refreshing Terraform state in-memory prior to plan...
The refreshed state will be used to calculate this plan, but will not be
persisted to local or remote state storage.


------------------------------------------------------------------------

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + github_repository.blog
      allow_merge_commit:                     "true"
      allow_rebase_merge:                     "true"
      allow_squash_merge:                     "true"
      archived:                               "false"
      description:                            "Patrick R. Donahue's Blog"
      name:                                   "blog"
      private:                                "false"

  + cloudflare_page_rule.redirect-apex
      actions.#:                              "1"
      actions.0.always_use_https:             "false"
      actions.0.disable_apps:                 "false"
      actions.0.disable_performance:          "false"
      actions.0.disable_security:             "false"
      actions.0.forwarding_url.#:             "1"
      actions.0.forwarding_url.0.status_code: "301"
      actions.0.forwarding_url.0.url:         "https://blog.prdonahue.com"
      priority:                               "1"
      status:                                 "active"
      target:                                 "prdonahue.com"
      zone:                                   "prdonahue.com"

  + cloudflare_page_rule.redirect-www
      actions.#:                              "1"
      actions.0.always_use_https:             "false"
      actions.0.disable_apps:                 "false"
      actions.0.disable_performance:          "false"
      actions.0.disable_security:             "false"
      actions.0.forwarding_url.#:             "1"
      actions.0.forwarding_url.0.status_code: "301"
      actions.0.forwarding_url.0.url:         "https://blog.prdonahue.com"
      priority:                               "1"
      status:                                 "active"
      target:                                 "www.prdonahue.com"
      zone:                                   "prdonahue.com"

  + cloudflare_record.apex
      domain:                                 "prdonahue.com"
      name:                                   "prdonahue.com"
      proxied:                                "true"
      type:                                   "CNAME"
      value:                                  "blog.prdonahue.com"

  + cloudflare_record.blog
      domain:                                 "prdonahue.com"
      name:                                   "blog.prdonahue.com"
      proxied:                                "true"
      type:                                   "CNAME"
      value:                                  "prdonahuedotcom.github.io"

  + cloudflare_record.www
      domain:                                 "prdonahue.com"
      name:                                   "www.prdonahue.com"
      proxied:                                "true"
      type:                                   "CNAME"
      value:                                  "blog.prdonahue.com"

  + cloudflare_zone_settings_override.zone-settings
      name:                                   "prdonahue.com"
      settings.#:                             "1"
      settings.0.automatic_https_rewrites:    "on"
      settings.0.ssl:                         "strict"
      settings.0.tls_1_3:                     "on"


Plan: 7 to add, 0 to change, 0 to destroy.
...
```

The plan looks good, so let's apply the changes. Output below has been trimmed for brevity:

```
$ terraform apply --auto-approve | grep -v "<computed>"
github_repository.blog: Creating...
...
cloudflare_record.apex: Creating...
...
cloudflare_page_rule.redirect-apex: Creating...
...
cloudflare_record.www: Creating...
...
cloudflare_record.blog: Creating...
...
cloudflare_page_rule.redirect-www: Creating...
...
cloudflare_zone_settings_override.zone-settings: Creating...

github_repository.blog: Creation complete after 2s (ID: blog)
cloudflare_record.apex: Creation complete after 3s (ID: d2e274b4992b37189f0bb023f56c4db2)
cloudflare_record.www: Creation complete after 3s (ID: 37f4b8c030ebc57ff419c013124ed66a)
cloudflare_record.blog: Creation complete after 3s (ID: 2e73f777a9f4df7819f438a4fa20b9a5)
cloudflare_zone_settings_override.zone-settings: Creation complete after 5s (ID: 6f870cfac3438e94d6190997cb6f0c41)
cloudflare_page_rule.redirect-apex: Creation complete after 6s (ID: db4443ce49ac6854c5472392368039cf)
cloudflare_page_rule.redirect-www: Creation complete after 7s (ID: 7bfb5a55d467eb5d891eb987fd2df30e)

Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
```

## Publish your blog

At this point we've got Cloudflare configured and a GitHub repository created. It's time to create your blog and publish your first blog post.

Before doing so, you'll want to choose a theme from https://themes.gohugo.io/. I've chosen to use the excellent [Hyde-X theme](https://github.com/zyro/hyde-x), which is a port of the Jekyll "Hyde" theme.

### i. Initialize the git repository and create the docs/ directory from which GitHub Pages will serve
```
$ cd ~/src/$PUBLIC_ZONE/$PUBLIC_HOST
$ git init
Initialized empty Git repository in /Users/pdonahue/src/prdonahue.com/blog/.git/

$ mkdir docs
$ echo $PUBLIC_FQDN > docs/CNAME
```

### ii. Create a new Hugo site and configure it to use your selected theme and output directory

First we'll create the site and add our selected theme as a [git submodule](https://git-scm.com/book/en/v2/Git-Tools-Submodules).

```
$ hugo new site hugo
Congratulations! Your new Hugo site is created in /Users/pdonahue/src/prdonahue.com/blog/hugo.

Just a few more steps and you're ready to go:

1. Download a theme into the same-named folder.
   Choose a theme from https://themes.gohugo.io/, or
   create your own with the "hugo new theme <THEMENAME>" command.
2. Perhaps you want to add some content. You can add single files
   with "hugo new <SECTIONNAME>/<FILENAME>.<FORMAT>".
3. Start the built-in live server via "hugo server".

Visit https://gohugo.io/ for quickstart guide and full documentation.

$ cd hugo
git submodule add https://github.com/zyro/hyde-x themes/hyde-x
Cloning into '/Users/pdonahue/src/prdonahue.com/blog/hugo/themes/hyde-x'...
remote: Counting objects: 456, done.
remote: Total 456 (delta 0), reused 0 (delta 0), pack-reused 456
Receiving objects: 100% (456/456), 273.88 KiB | 0 bytes/s, done.
Resolving deltas: 100% (209/209), done.
Checking connectivity... done.
```

Then, we'll create a configuration file. You'll need to customize the following fields:

* `author`
* `profilePic` (place a 200x200 image in hugo/static)
* `gravatarHash` (used if `profilePic` is not set)
* `github`, `linkedin`, `twitter`

You'll also want to personalize:

* `theme`
* `tagline`
* `highlight` (see list of styles [here](https://highlightjs.org/static/demo/))

```
$ cat <<EOF | tee config.toml
baseURL = "https://$PUBLIC_FQDN"
title = "$REPO_AND_BLOG_DESC"
languageCode = "en-us"
theme = "hyde-x"
publishDir = "../docs"

disqusShortname = "prdblog"
MetaDataFormat = "toml"
paginate = 10

linenos = "inline"

[author]
    name = "Patrick R. Donahue"

[permalinks]
    post = "/blog/:year/:month/:day/:title/"

[taxonomies]
    category = "categories"

[params]
    profilePic = "me-200x200.png"
    gravatarHash = "bc3f5fdfd3bf7ee89c7cd196c916714a"
    truncate = true
    theme = "theme-base-05"
    highlight = "monokai-sublime"
    customCSS = ""

    tagline = "San Francisco resident, Boston native."
    home = "Blog"
    #googleAnalytics = ""

    github = "https://github.com/prdonahue"
    linkedin = "https://www.linkedin.com/in/prdonahue/"
    twitter = "https://twitter.com/prdonahue"

    rss = true
```

### iii. Create your first blog post, preview it, and then build the site statically

Finally, time to write a post! Follow the instructions below to create a new post in Markdown format.

```
$ mkdir content/post
$ cat <<EOF | tee content/post/terraforming-static-blog-with-hugo-github-pages-and-cloudflare.md
---
title: "Terraforming a static blog with Hugo, GitHub Pages, and Cloudflare"
date: 2018-06-10T19:39:22-07:00
draft: false
categories:
- hugo
- cloudflare
- terraform
- github-pages
- disqus
---

Blog post goes here!
EOF
```

To preview your post you can run hugo in local server mode and have it show unpublished drafts. Any changes you make to the content will be live updated in the browser.

```
$ hugo server -D

                   | EN  
+------------------+----+
  Pages            | 18  
  Paginator pages  |  0  
  Non-page files   |  0  
  Static files     | 91  
  Processed images |  0  
  Aliases          |  1  
  Sitemaps         |  1  
  Cleaned          |  0  

Total in 24 ms
Watching for changes in /Users/pdonahue/src/prdonahue.com/blog/hugo/{content,data,layouts,static,themes}
Watching for config changes in /Users/pdonahue/src/prdonahue.com/blog/hugo/config.toml
Serving pages from memory
Running in Fast Render Mode. For full rebuilds on change: hugo server --disableFastRender
Web Server is available at http://localhost:1313/ (bind address 127.0.0.1)
Press Ctrl+C to stop

^C
```

Assuming the page looks good, it's time to build it into the `docs/` directory, which we'll configure GitHub Pages to read from in the next step.

```
$ hugo

                   | EN  
+------------------+----+
  Pages            | 18  
  Paginator pages  |  0  
  Non-page files   |  0  
  Static files     | 91  
  Processed images |  0  
  Aliases          |  1  
  Sitemaps         |  1  
  Cleaned          |  0  

Total in 36 ms
```

### iv. Upload everything to GitHub

Before we make our first commit, let's tell Git to ignore Terraform's plugins directory any state files. Often times state files contain sensitive information so they should be removed for security reasons. Even if they don't, you can easily [run into conflicts](https://www.terraform.io/docs/state/purpose.html#syncing); if you're working with multiple people on the same Terraform project you should look into [remote state storage](https://www.terraform.io/docs/state/remote.html).

```
$ cat <<EOF | tee -a .gitignore
.terraform/
*tfstate*

$ git add .
$ git commit -m "Initial commit with first blog post."
[master (root-commit) dee3a2d] Initial commit with first blog post.
 249 files changed, 19066 insertions(+)
 create mode 100644 .gitignore
 create mode 100644 .gitmodules
 create mode 100644 docs/404.html
...

$ git remote add origin git@github.com:prdonahuedotcom/blog.git
$ git push
Counting objects: 49, done.
Delta compression using up to 8 threads.
Compressing objects: 100% (44/44), done.
Writing objects: 100% (49/49), 92.35 KiB | 0 bytes/s, done.
Total 49 (delta 5), reused 0 (delta 0)
remote: Resolving deltas: 100% (5/5), done.
To git@github.com:prdonahuedotcom/blog.git
 * [new branch]      master -> master
```

### v. Set GitHub Pages to serve from your output directory

With our blog repository pushed, we have one last step. By default GitHub Pages looks to serve context from the root of the repository, but because we're using that to store Hugo and our Terraform config files (not just the statically generated content), we need to tell it to use `docs/`.

Browse to the settings page of your repository and scroll toward the bottom until you hit "GitHub Pages". Set the value under Source to read "master branch /docs folder", as shown below.

![GitHub Pages](/github-pages-docs.png)

## Wrapping up

If you've made it this far you should have a highly performant blog available on your domain. For me, that's https://blog.prdonahue.com. 

In the future, I plan to build on this blog post to show off additional methods for simplifying your infrastructure management. Let me know in the comments below if anything needs additional detail (or if there's anything you'd like to see covered in a follow-up post).