# frozen_string_literal: true

require "test_helper"
require "cwt/git"
require "tmpdir"
require "fileutils"

module Cwt
  class TestGitIntegration < Minitest::Test
    def setup
      # Create a temporary directory for our test git repo
      @tmpdir = Dir.mktmpdir("cwt-test-")
      @original_dir = Dir.pwd
      Dir.chdir(@tmpdir)

      # Initialize a git repo with an initial commit
      system("git init -q")
      system("git config user.email 'test@test.com'")
      system("git config user.name 'Test User'")
      File.write("README.md", "# Test Repo")
      system("git add README.md")
      system("git commit -q -m 'Initial commit'")
    end

    def teardown
      Dir.chdir(@original_dir)
      FileUtils.rm_rf(@tmpdir)
    end

    # ========== Setup Marker Tests ==========

    def test_add_worktree_creates_setup_marker
      result = Git.add_worktree("test-session")

      assert result[:success], "Worktree should be created"
      assert File.exist?(File.join(result[:path], Git::SETUP_MARKER)),
             "Setup marker should exist in new worktree"
    end

    def test_needs_setup_returns_true_for_new_worktree
      result = Git.add_worktree("test-session")

      assert Git.needs_setup?(result[:path]),
             "needs_setup? should return true for new worktree"
    end

    def test_mark_setup_complete_removes_marker
      result = Git.add_worktree("test-session")
      path = result[:path]

      assert Git.needs_setup?(path), "Should need setup initially"

      Git.mark_setup_complete(path)

      refute Git.needs_setup?(path), "Should not need setup after marking complete"
      refute File.exist?(File.join(path, Git::SETUP_MARKER)),
             "Marker file should be deleted"
    end

    def test_needs_setup_returns_false_for_worktree_without_marker
      result = Git.add_worktree("test-session")
      path = result[:path]

      # Manually remove the marker
      File.delete(File.join(path, Git::SETUP_MARKER))

      refute Git.needs_setup?(path),
             "needs_setup? should return false when marker doesn't exist"
    end

    # ========== Setup Execution Tests ==========

    def test_run_setup_visible_executes_custom_script
      result = Git.add_worktree("test-session")
      path = result[:path]

      # Create .cwt/setup script
      FileUtils.mkdir_p(".cwt")
      File.write(".cwt/setup", "#!/bin/bash\necho 'setup ran' > setup_ran.txt")
      FileUtils.chmod(0o755, ".cwt/setup")

      # Capture output
      output = capture_io { Git.run_setup_visible(path) }.join

      assert File.exist?(File.join(path, "setup_ran.txt")),
             "Setup script should have created file in worktree"
      assert_match(/Running .cwt\/setup/, output,
             "Should show setup header")
    end

    def test_run_setup_visible_falls_back_to_symlinks
      result = Git.add_worktree("test-session")
      path = result[:path]

      # Create files to symlink in root
      File.write(".env", "SECRET=value")
      FileUtils.mkdir_p("node_modules")
      File.write("node_modules/.keep", "")

      # No .cwt/setup script exists
      Git.run_setup_visible(path)

      # Check symlinks were created
      assert File.symlink?(File.join(path, ".env")),
             ".env should be symlinked"
      assert File.symlink?(File.join(path, "node_modules")),
             "node_modules should be symlinked"
    end

    def test_run_setup_visible_does_not_symlink_when_script_exists
      result = Git.add_worktree("test-session")
      path = result[:path]

      # Create files to symlink in root
      File.write(".env", "SECRET=value")

      # Create .cwt/setup script (does nothing)
      FileUtils.mkdir_p(".cwt")
      File.write(".cwt/setup", "#!/bin/bash\n# do nothing")
      FileUtils.chmod(0o755, ".cwt/setup")

      capture_io { Git.run_setup_visible(path) }

      refute File.exist?(File.join(path, ".env")),
             ".env should NOT be symlinked when custom script exists"
    end

    def test_cwt_root_env_var_is_set_for_setup
      result = Git.add_worktree("test-session")
      path = result[:path]

      # Create .cwt/setup script that writes CWT_ROOT to a file
      FileUtils.mkdir_p(".cwt")
      File.write(".cwt/setup", "#!/bin/bash\necho \"$CWT_ROOT\" > cwt_root.txt")
      FileUtils.chmod(0o755, ".cwt/setup")

      capture_io { Git.run_setup_visible(path) }

      root_file = File.join(path, "cwt_root.txt")
      assert File.exist?(root_file), "Script should have created cwt_root.txt"
      # Use realpath to handle macOS /var -> /private/var symlink
      assert_equal File.realpath(@tmpdir), File.read(root_file).strip,
             "CWT_ROOT should be set to the repo root"
    end

    # ========== Teardown Tests ==========

    def test_run_teardown_executes_script
      result = Git.add_worktree("test-session")
      path = result[:path]

      # Create .cwt/teardown script using CWT_ROOT env var
      FileUtils.mkdir_p(".cwt")
      File.write(".cwt/teardown", "#!/bin/bash\necho 'teardown ran' > \"$CWT_ROOT/teardown_ran.txt\"")
      FileUtils.chmod(0o755, ".cwt/teardown")

      output = capture_io { Git.run_teardown(path) }.join

      assert File.exist?(File.join(@tmpdir, "teardown_ran.txt")),
             "Teardown script should have created file"
      assert_match(/Running .cwt\/teardown/, output,
             "Should show teardown header")
    end

    def test_run_teardown_returns_ran_false_when_no_script
      result = Git.add_worktree("test-session")
      path = result[:path]

      teardown_result = Git.run_teardown(path)

      refute teardown_result[:ran], "Should return ran: false when no script"
    end

    def test_run_teardown_returns_success_status
      result = Git.add_worktree("test-session")
      path = result[:path]

      # Create .cwt/teardown script that succeeds
      FileUtils.mkdir_p(".cwt")
      File.write(".cwt/teardown", "#!/bin/bash\nexit 0")
      FileUtils.chmod(0o755, ".cwt/teardown")

      teardown_result = capture_io { Git.run_teardown(path) }.last
      teardown_result = Git.run_teardown(path)

      assert teardown_result[:ran], "Should return ran: true"
      assert teardown_result[:success], "Should return success: true"
    end

    def test_run_teardown_returns_failure_status
      result = Git.add_worktree("test-session")
      path = result[:path]

      # Create .cwt/teardown script that fails
      FileUtils.mkdir_p(".cwt")
      File.write(".cwt/teardown", "#!/bin/bash\nexit 1")
      FileUtils.chmod(0o755, ".cwt/teardown")

      teardown_result = capture_io { Git.run_teardown(path) }.last
      teardown_result = Git.run_teardown(path)

      assert teardown_result[:ran], "Should return ran: true"
      refute teardown_result[:success], "Should return success: false"
    end

    # ========== Remove Worktree with Teardown Tests ==========

    def test_remove_worktree_runs_teardown
      result = Git.add_worktree("test-session")
      path = result[:path]
      Git.mark_setup_complete(path)

      # Create .cwt/teardown script using CWT_ROOT env var
      FileUtils.mkdir_p(".cwt")
      File.write(".cwt/teardown", "#!/bin/bash\necho 'teardown ran' > \"$CWT_ROOT/teardown_evidence.txt\"")
      FileUtils.chmod(0o755, ".cwt/teardown")

      capture_io { Git.remove_worktree(path) }

      assert File.exist?(File.join(@tmpdir, "teardown_evidence.txt")),
             "Teardown should have run before removal"
    end

    def test_remove_worktree_fails_on_teardown_failure_without_force
      result = Git.add_worktree("test-session")
      path = result[:path]
      Git.mark_setup_complete(path)

      # Create .cwt/teardown script that fails
      FileUtils.mkdir_p(".cwt")
      File.write(".cwt/teardown", "#!/bin/bash\nexit 1")
      FileUtils.chmod(0o755, ".cwt/teardown")

      remove_result = capture_io { Git.remove_worktree(path) }.last
      remove_result = Git.remove_worktree(path)

      refute remove_result[:success], "Should fail when teardown fails"
      assert_match(/teardown.*failed/i, remove_result[:error])
      assert Dir.exist?(path), "Worktree should still exist"
    end

    def test_remove_worktree_succeeds_on_teardown_failure_with_force
      result = Git.add_worktree("test-session")
      path = result[:path]
      Git.mark_setup_complete(path)

      # Create .cwt/teardown script that fails
      FileUtils.mkdir_p(".cwt")
      File.write(".cwt/teardown", "#!/bin/bash\nexit 1")
      FileUtils.chmod(0o755, ".cwt/teardown")

      remove_result = capture_io { Git.remove_worktree(path, force: true) }.last
      remove_result = Git.remove_worktree(path, force: true)

      assert remove_result[:success], "Should succeed with force: true"
      refute Dir.exist?(path), "Worktree should be removed"
    end

    # ========== Full Workflow Tests ==========

    def test_full_workflow_create_setup_teardown_delete
      # 1. Create worktree
      result = Git.add_worktree("full-workflow")
      path = result[:path]
      assert result[:success]
      assert Git.needs_setup?(path)

      # 2. Create setup and teardown scripts using CWT_ROOT env var
      FileUtils.mkdir_p(".cwt")
      File.write(".cwt/setup", "#!/bin/bash\necho 'setup' > setup.log")
      File.write(".cwt/teardown", "#!/bin/bash\necho 'teardown' > \"$CWT_ROOT/teardown.log\"")
      FileUtils.chmod(0o755, ".cwt/setup")
      FileUtils.chmod(0o755, ".cwt/teardown")

      # 3. Run setup (simulating first resume)
      capture_io { Git.run_setup_visible(path) }
      Git.mark_setup_complete(path)
      assert File.exist?(File.join(path, "setup.log"))
      refute Git.needs_setup?(path)

      # 4. Second resume should NOT run setup
      refute Git.needs_setup?(path), "Setup should not run again"

      # 5. Delete worktree (runs teardown)
      # Force needed because setup.log is an untracked file
      capture_io { Git.remove_worktree(path, force: true) }
      assert File.exist?(File.join(@tmpdir, "teardown.log"))
      refute Dir.exist?(path)
    end
  end
end
