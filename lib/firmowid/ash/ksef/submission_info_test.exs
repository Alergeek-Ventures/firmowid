defmodule Firmowid.Ash.Ksef.SubmissionInfoTest do
  @moduledoc """
  Tests for SubmissionInfo status helper functions.
  """

  use ExUnit.Case, async: true

  alias Firmowid.Ash.Ksef.SubmissionInfo

  describe "submitted?/1" do
    test "returns true for :submitted status" do
      assert SubmissionInfo.submitted?(%SubmissionInfo{status: :submitted})
    end

    test "returns false for other statuses" do
      refute SubmissionInfo.submitted?(%SubmissionInfo{status: :not_submitted})
      refute SubmissionInfo.submitted?(%SubmissionInfo{status: :submitting})
      refute SubmissionInfo.submitted?(%SubmissionInfo{status: :failed})
    end
  end

  describe "submitting?/1" do
    test "returns true for :submitting status" do
      assert SubmissionInfo.submitting?(%SubmissionInfo{status: :submitting})
    end

    test "returns false for other statuses" do
      refute SubmissionInfo.submitting?(%SubmissionInfo{status: :not_submitted})
      refute SubmissionInfo.submitting?(%SubmissionInfo{status: :submitted})
      refute SubmissionInfo.submitting?(%SubmissionInfo{status: :failed})
    end
  end

  describe "failed?/1" do
    test "returns true for :failed status" do
      assert SubmissionInfo.failed?(%SubmissionInfo{status: :failed})
    end

    test "returns false for other statuses" do
      refute SubmissionInfo.failed?(%SubmissionInfo{status: :not_submitted})
      refute SubmissionInfo.failed?(%SubmissionInfo{status: :submitted})
      refute SubmissionInfo.failed?(%SubmissionInfo{status: :submitting})
    end
  end

  describe "not_submitted?/1" do
    test "returns true for :not_submitted status" do
      assert SubmissionInfo.not_submitted?(%SubmissionInfo{status: :not_submitted})
    end

    test "returns false for other statuses" do
      refute SubmissionInfo.not_submitted?(%SubmissionInfo{status: :submitted})
      refute SubmissionInfo.not_submitted?(%SubmissionInfo{status: :submitting})
      refute SubmissionInfo.not_submitted?(%SubmissionInfo{status: :failed})
    end
  end

  describe "attempted?/1" do
    test "returns false for :not_submitted" do
      refute SubmissionInfo.attempted?(%SubmissionInfo{status: :not_submitted})
    end

    test "returns true for all other statuses" do
      assert SubmissionInfo.attempted?(%SubmissionInfo{status: :submitted})
      assert SubmissionInfo.attempted?(%SubmissionInfo{status: :submitting})
      assert SubmissionInfo.attempted?(%SubmissionInfo{status: :failed})
    end
  end
end
