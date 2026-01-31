# frozen_string_literal: true

require "test_helper"
require "cwt/git"
require "mocha/minitest"

module Cwt
  class TestGit < Minitest::Test
    def test_get_commit_ages_empty_shas
      ages = Git.get_commit_ages([])
      assert_equal({}, ages)
    end

    def test_get_commit_ages_parses_output
      Open3.expects(:capture2)
           .returns(["abc123|2 hours ago\ndef456|3 days ago\n", mock(success?: true)])

      ages = Git.get_commit_ages(["abc123", "def456"])

      assert_equal "2 hours ago", ages["abc123"]
      assert_equal "3 days ago", ages["def456"]
    end

    def test_get_status_returns_dirty_hash
      path = "/some/path"

      Open3.expects(:capture2)
           .with("git", "--no-optional-locks", "-C", path, "status", "--porcelain")
           .returns(["M file.txt\n", mock(success?: true)])

      result = Git.get_status(path)
      assert result[:dirty]
    end

    def test_get_status_returns_clean_hash
      path = "/some/path"

      Open3.expects(:capture2)
           .with("git", "--no-optional-locks", "-C", path, "status", "--porcelain")
           .returns(["", mock(success?: true)])

      result = Git.get_status(path)
      refute result[:dirty]
    end

    def test_prune_worktrees
      Open3.expects(:capture2)
           .with("git", "worktree", "prune")
           .returns(["", nil])

      Git.prune_worktrees
    end

    def test_prune_worktrees_with_repo_root
      Open3.expects(:capture2)
           .with("git", "-C", "/repo/root", "worktree", "prune")
           .returns(["", nil])

      Git.prune_worktrees(repo_root: "/repo/root")
    end
  end
end
