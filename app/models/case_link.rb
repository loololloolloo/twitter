# The join between a report and the case it belongs to. It is a row rather
# than a `case_id` column on reports so the link itself is auditable: which
# operator attached the report, and when. A report is on at most one case, so
# the unique index on report_id is the rule the model leans on.
class CaseLink < ApplicationRecord
  belongs_to :moderation_case
  belongs_to :report
  belongs_to :linked_by, class_name: "User", optional: true

  validates :report_id, uniqueness: { message: "is already on a case" }
end
