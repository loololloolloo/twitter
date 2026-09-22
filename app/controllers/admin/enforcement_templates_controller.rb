module Admin
  # Enforcement macros: the canned action-and-reason combinations an operator
  # applies so the same violation is described the same way every time.
  #
  # The screen owns the wording, not the authority. A macro names an action and
  # the text to record; applying it still runs that action through the same
  # guards as the hand-written form, so managing macros is a separate grant
  # (users.templates) from holding the actions themselves. A permanent ban is
  # deliberately not offered: it needs a second operator's approval and a
  # one-step macro would route around that control.
  class EnforcementTemplatesController < AdminController
    before_action :require_manage_permission

    def index
      @templates = EnforcementTemplate.recent.limit(200)
      @active_count = EnforcementTemplate.active.count
    end

    def create
      template = EnforcementTemplate.new(
        name: params[:name],
        action_key: params[:action_key],
        reason: params[:reason],
        duration: params[:duration].to_s,
        category: params[:category].to_s,
        created_by_id: current_user.id
      )

      if template.save
        audit!("users.templates", target: "enforcement_template:#{template.id}",
                                  detail: "created #{template.action_key} macro #{template.name.inspect}")
        redirect_to admin_enforcement_templates_path, notice: "Macro #{template.name.inspect} created."
      else
        redirect_to admin_enforcement_templates_path, alert: template.errors.full_messages.to_sentence
      end
    end

    # Editing the shared wording changes what every operator records, so it is a
    # real write and carries the same permission as creating one. The row is
    # kept when disabled so the audit trail can still name the macro an operator
    # applied.
    def update
      template = EnforcementTemplate.find_by(id: params[:id])
      return redirect_to admin_enforcement_templates_path, alert: "Macro not found." if template.nil?

      if template.update(
        name: params[:name],
        action_key: params[:action_key],
        reason: params[:reason],
        duration: params[:duration].to_s,
        category: params[:category].to_s
      )
        audit!("users.templates", target: "enforcement_template:#{template.id}",
                                  detail: "edited #{template.action_key} macro #{template.name.inspect}")
        redirect_to admin_enforcement_templates_path, notice: "Macro #{template.name.inspect} updated."
      else
        redirect_to admin_enforcement_templates_path, alert: template.errors.full_messages.to_sentence
      end
    end

    def toggle
      template = EnforcementTemplate.find_by(id: params[:id])
      return redirect_to admin_enforcement_templates_path, alert: "Macro not found." if template.nil?

      template.update!(active: !template.active)
      audit!("users.templates", target: "enforcement_template:#{template.id}",
                                detail: "#{template.active ? 'enabled' : 'disabled'} macro #{template.name.inspect}")
      redirect_to admin_enforcement_templates_path,
                  notice: "#{template.name.inspect} is now #{template.active ? 'active' : 'off'}."
    end

    private

    def require_manage_permission
      require_permission!("users.templates")
    end
  end
end
