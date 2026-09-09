# Publication Guide

## Current State

`ruby-drmanhattan` is structured as a standalone Ruby gem.

Current coordinates:

- gem: `ruby-drmanhattan`
- version: `0.1.2`
- repository: `github.com/animalab-netizen/ruby-drmanhattan`

## Distribution Model

The gem is intended for:

- direct RubyGems distribution as the public Ruby DrManhattan runtime
- consumption by validation projects and service-side examples
- installation without any private gem server requirement

## Installation

```bash
gem install ruby-drmanhattan
```

## Release Checklist

1. Run `ruby -c lib/ruby_drmanhattan/runtime.rb`
2. Run `ruby -c test/runtime_test.rb`
3. Run `ruby test/runtime_test.rb`
4. Run `gem build ruby-drmanhattan.gemspec`
5. Update `CHANGELOG.md`
6. Confirm version in `ruby-drmanhattan.gemspec`
7. Commit release metadata
8. Create and push tag `v0.1.2`
9. Confirm `RUBYGEMS_API_KEY` is configured in GitHub Actions secrets
10. Verify publication on RubyGems

## Workflow Notes

- CI runs from `.github/workflows/ci.yml`
- tag releases run from `.github/workflows/release.yml`
- release publication requires `RUBYGEMS_API_KEY`
- GitHub Releases are created automatically for version tags
