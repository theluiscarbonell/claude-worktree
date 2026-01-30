# frozen_string_literal: true

require "test_helper"
require "cwt/git"
require "mocha/minitest"

module Cwt
  class TestGit < Minitest::Test
    def test_parse_porcelain
      output = <<~PORCELAIN
        worktree /Users/bengarcia/projects/claude-worktree
        HEAD d8a8d1b1c6e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1
        branch refs/heads/main

        worktree /Users/bengarcia/projects/claude-worktree/.worktrees/feature-1
        HEAD a1b2c3d4e5f6g7h8i9j0
        branch refs/heads/feature-1
      PORCELAIN

      worktrees = Git.send(:parse_porcelain, output)
      
      assert_equal 2, worktrees.size
      assert_equal "/Users/bengarcia/projects/claude-worktree", worktrees[0][:path]
      assert_equal "main", worktrees[0][:branch]
      assert_equal "feature-1", worktrees[1][:branch]
    end

    def test_add_worktree_success
      Open3.expects(:capture3)
           .with("git", "worktree", "add", "-b", "new-session", ".worktrees/new-session")
           .returns(["stdout", "", mock(success?: true)])

      # Mock directory creation and marker
      FileUtils.expects(:mkdir_p).with(".worktrees")
      Git.expects(:mark_needs_setup).with(".worktrees/new-session")

      result = Git.add_worktree("new-session")
      assert result[:success]
      assert_equal ".worktrees/new-session", result[:path]
    end

    def test_add_worktree_failure
      Open3.expects(:capture3)
           .returns(["", "error message", mock(success?: false)])
      
      FileUtils.stubs(:mkdir_p)

      result = Git.add_worktree("bad-session")
      refute result[:success]
      assert_equal "error message", result[:error]
    end

    def test_setup_default_symlinks
      root = Dir.pwd
      target = ".worktrees/test"

      # Expect checks for source files
      File.expects(:exist?).with(File.join(root, ".env")).returns(true)
      File.expects(:exist?).with(File.join(root, "node_modules")).returns(true)

      # Expect checks for target files (don't exist yet)
      File.expects(:exist?).with(File.join(target, ".env")).returns(false)
      File.expects(:exist?).with(File.join(target, "node_modules")).returns(false)

      # Expect symlinks
      FileUtils.expects(:ln_s).with(File.join(root, ".env"), File.join(target, ".env"))
      FileUtils.expects(:ln_s).with(File.join(root, "node_modules"), File.join(target, "node_modules"))

      Git.send(:setup_default_symlinks, target, root)
    end

    def test_needs_setup_checks_marker_file
      path = ".worktrees/test"
      marker = File.join(path, Git::SETUP_MARKER)

      File.expects(:exist?).with(marker).returns(true)
      assert Git.needs_setup?(path)

      File.expects(:exist?).with(marker).returns(false)
      refute Git.needs_setup?(path)
    end

    def test_mark_setup_complete_removes_marker
      path = ".worktrees/test"
      marker = File.join(path, Git::SETUP_MARKER)

      File.expects(:exist?).with(marker).returns(true)
      File.expects(:delete).with(marker)

      Git.mark_setup_complete(path)
    end
  end
end
