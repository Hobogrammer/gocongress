require "spec_helper"

describe AttendeesController do
  render_views
  let(:activities) { 1.upto(3).map{ create :activity } }

  context "as a visitor" do
    describe "#create" do
      it "is forbidden for visitors" do
        attrs = attributes_for :attendee
        expect { post :create, attendee: attrs, year: attrs[:year]
          }.to_not change{ Attendee.count }
        response.should be_forbidden
      end
    end

    describe "#edit" do
      it "is forbidden" do
        a = create :attendee
        get :edit, :id => a.id, :year => a.year
        response.should be_forbidden
      end
    end

    describe "#index" do
      render_views

      it "succeeds" do
        get :index, :year => Time.now.year
        response.should be_successful
      end

      it "lists attendees with at least one plan" do
        p = create :plan
        a = create :attendee, {plans: [p]}
        a2 = create :attendee, {plans: []}
        get :index, year: a.year
        response.should be_successful
        assigns(:attendees).should include(a)
        assigns(:attendees).should_not include(a2)
      end
    end

    describe "#new" do
      it "is forbidden" do
        get :new, :year => Time.now.year
        response.should be_forbidden
      end
    end
  end

  context "as a user" do
    let!(:attendee) { create :attendee }
    let!(:user) { attendee.user }
    before { sign_in user }

    describe "#create" do
      it "succeeds under own account" do
        a = accessible_attributes_for(:attendee).merge(:user_id => user.id)
        expect { post :create, :attendee => a, :year => user.year
          }.to change { user.attendees.count }.by(+1)
        response.should redirect_to \
          user_terminus_path(:user_id => user.id, :year => user.year)
      end

      it "fails without any attributes" do
        attrs = {:user_id => user.id}
        expect { post :create, :attendee => attrs, :year => user.year
          }.to_not change { Attendee.count }
        response.should render_template :new
        assigns(:attendee).errors.should_not be_empty
      end

      it "is forbidden to create attendee under a different user" do
        user_two = create :user
        a = accessible_attributes_for(:attendee).merge(:user_id => user_two.id)
        expect { post :create, :attendee => a, :year => user_two.year
          }.not_to change { Attendee.count }
        response.should be_forbidden
      end

      it "given invalid attributes it does not create attendee" do
        attrs = accessible_attributes_for(:attendee).merge(:user_id => user.id)
        attrs[:gender] = "zzzz" # invalid, obviously
        expect {
          post :create, attendee: attrs, year: user.year
        }.to_not change{ Attendee.count }
        assigns(:attendee).errors.should include(:gender)
      end

      it "minors can specify the name of their guardian" do
        attrs = accessible_attributes_for(:minor).merge(:user_id => user.id)
        attrs[:guardian_full_name] = "Mommy Moo"
        expect {
          post :create, attendee: attrs, year: user.year
        }.to change{ Attendee.count }.by(+1)
      end
    end

    describe "#destroy" do
      it "destroys the attendee" do
        expect {
          delete :destroy, :id => attendee.id, :year => attendee.year
        }.to change{ user.attendees.count }.by(-1)
        response.should redirect_to user_path(user)
      end

      it "is forbidden to destroy attendee from other user" do
        a = create :attendee
        user_two = a.user
        expect { delete :destroy, :id => a.id, :year => a.year
          }.to_not change { Attendee.count }
        response.should be_forbidden
      end
    end

    describe "#edit" do
      it "cannot edit another user's attendee" do
        a = create :attendee
        get :edit, :id => a.id, :year => a.year
        response.should be_forbidden
      end

      it "user can edit their own attendees" do
        get :edit, :id => user.attendees.sample.id, :year => user.year
        response.should be_successful
        response.should render_template 'edit'
      end

      it "shows disabled plans, but only if attendee already has them" do
        plan = create :plan, :disabled => true
        attendee.plans << plan
        attendee.get_plan_qty(plan.id).should == 1

        plan2 = create :plan, :disabled => true, \
          :name => "Plan Deux", :plan_category => plan.plan_category

        get :edit,
          :id => attendee.id,
          :year => attendee.year

        assigns(:plans).should include(plan)
        assigns(:plans).map(&:name).should_not include(plan2.name)
      end
    end

    describe "#index" do
      it "excludes attendees with zero plans" do
        a1 = create :attendee
        a2 = create :attendee
        a1.plans << create(:plan)
        get :index, year: a1.year
        assigns(:attendees).should_not include(a2)
      end
    end

    describe '#new' do
      it 'succeeds' do
        get :new, :year => user.year
        response.should be_successful
      end
    end

    describe "#update" do

      def put_update attendee_attrs = {}
        put :update,
          attendee: attendee_attrs,
          id: attendee.id,
          year: attendee.year
      end

      def datetime_attrs arpt_date, arpt_time
        {
          :airport_arrival_date => arpt_date,
          :airport_arrival_time => arpt_time
        }
      end

      it "updates a trivial field" do
        expect { put_update :given_name => 'banana'
          }.to change { attendee.reload.given_name }
      end

      it "redirects to terminus if successful" do
        put_update
        response.should redirect_to \
          user_terminus_path(:user_id => user.id, :year => user.year)
      end

      it "updates valid airport datetimes" do
        d = "#{attendee.year}-01-01"
        put_update datetime_attrs(d, "8:00 PM")
        attendee.reload.airport_arrival.should be_present
        attendee.airport_arrival.strftime("%Y-%m-%d %H:%M").should == "#{d} 20:00"
      end

      it "does not update invalid airport date" do
        put_update datetime_attrs("1/1/#{attendee.year}", "8:00 PM")
        attendee.reload.airport_arrival.should be_nil
        assigns(:attendee).errors[:base].should_not be_empty
      end

      it "does not update invalid airport time" do
        valid_date = "#{attendee.year}-01-01"
        put_update datetime_attrs(valid_date, "7:77 PM")
        attendee.reload.airport_arrival.should be_nil
        assigns(:attendee).errors[:base].should_not be_empty
      end

      it "does not update admin fields" do
        expect { put_update :comment => 'banana'
          }.to_not change { attendee.reload.comment }
      end

      it "is forbidden to update another user's attendee" do
        a = create :attendee
        put :update, :id => a.id, :attendee => a.attributes, :year => a.year
        response.should be_forbidden
      end

      context "activities" do
        it "can add activities to their own attendee" do
          expect { update_activities(attendee, activities) }.to \
            change { attendee.activities.count }.by(activities.length)
        end

        it "cannot add activities to attendee belonging to someone else" do
          attendee2 = create :attendee
          expect { update_activities(attendee2, activities) }.to_not \
            change { attendee2.activities.count }
          response.status.should == 403
        end

        it "cannot add disabled activities" do
          activities << create(:activity, disabled: true)
          expect { update_activities(attendee, activities) }.to_not \
            change { attendee.activities.count }
        end
      end

      context "plans" do
        let(:plan) { create :plan }

        def put_update plan
          put :update, :year => 2012, :id => attendee.id, :"plan_#{plan.id}_qty" => 1
        end

        it "updates the attendee's plans in the specified category" do
          put_update plan
          attendee.plans.should include(plan)
        end

        it "can clear own attendee plans" do
          attendee.plans << plan
          attendee.plans.should include(plan)
          submit_plans_form attendee, {}
          attendee.reload.plans.should be_empty
        end

        it "can deselect a plan" do
          attendee.plans << plan
          attendee.plans.should include(plan)
          submit_plans_form attendee, params_for_plan(plan, 0)
          attendee.reload.plans.should_not include(plan)
        end

        it "can select a plan for own attendee" do
          attendee.plans.should be_empty
          expect { submit_plans_form attendee, params_for_plan(plan, 1)
            }.to change { attendee.plans.count }.by(+1)
          attendee.reload.plans.should include(plan)
        end

        it "cannot select plan for attendee belonging to someone else" do
          a = create :attendee
          expect { submit_plans_form a, params_for_plan(plan, 1)
            }.to_not change { a.plans.count }
          response.should be_forbidden
        end

        context "when attendee selects a disabled plan" do
          let(:plan) { create :plan, disabled: true }

          context "and attendee already has that disabled plan" do
            before do
              attendee.plans << plan
            end

            it "should allow attendee to keep the plan" do
              put_update plan
              attendee.plans.should include(plan)
            end
          end

          context "and attendee does not already have that disabled plan" do
            it "should not allow attendee to select the disabled plan" do
              put_update plan
              attendee.plans.should_not include(plan)
            end
          end
        end

        context "when attendee un-selects a disabled plan" do
          let(:plan) { create :plan, disabled: true, name: "Numero Uno" }
          let(:plan2) { create :plan, name: "Deux", :plan_category => plan.plan_category }
          before do
            attendee.plans << plan
          end

          it "does not allow them to un-select the plan" do
            put :update,
              :year => 2012,
              :id => attendee.id,
              :plan_category_id => plan.plan_category.id,
              :"plan_#{plan2.id}_qty" => 1
            attendee.reload
            attendee.plans.map(&:name).should include(plan.name)
            response.should render_template(:edit)
          end
        end

        it "stays on the same page when there is an error registering plans" do
          Registration::Registration.any_instance.stub(:register_plans).and_return(["derp"])
          put :update, :year => 2012, :id => attendee.id
          response.should be_successful
          response.should render_template(:edit)
        end

        context "when the category is mandatory" do
          let(:cat) { create :plan_category, mandatory: true }
          let!(:plan) { create :plan, plan_category: cat }

          it "a quantity of one saves an AttendeePlan record" do
            expect { put_update plan }.to \
              change{ attendee.plans.count }.from(0).to(1)
          end
        end
      end

      context "discounts" do
        let(:a) { user.attendees.sample }

        it "can claim non-automatic discounts" do
          a.discounts.should be_empty
          d = create :nonautomatic_discount
          attrs = {:discount_ids => [d.id]}

          # the checkbox list can include extra empty strings
          attrs[:discount_ids] << ""

          put :update, :id => a.id, :attendee => attrs, :year => a.year
          a.reload.discounts.should == [d]
        end

        it "cannot claim automatic discounts" do
          a.discounts.should be_empty
          d = create :automatic_discount
          attrs = {:discount_ids => [d.id]}
          put :update, :id => a.id, :attendee => attrs, :year => a.year
          a.reload.discounts.should_not include(d)
        end
      end

    end
  end

  context "as an admin" do
    let(:admin) { create :admin }
    before { sign_in admin }

    describe "#create" do
      it "succeeds, creating attendee under any user" do
        u = create :user
        a = accessible_attributes_for(:attendee).merge(:user_id => u.id)
        expect { post :create, :attendee => a, :year => u.year
          }.to change { u.attendees.count }.by(+1)
      end
    end

    describe "#destroy" do
      it "can destroy any attendee" do
        a = create :attendee
        expect { delete :destroy, :id => a.id, :year => a.year
          }.to change { a.user.attendees.count }.by(-1)
        response.should redirect_to user_path(a.user)
        flash[:notice].should == 'Attendee deleted'
      end

      it "can destroy primary attendee" do
        prim = create :primary_attendee
        expect { delete :destroy, :id => prim.id, :year => prim.year
          }.to change { Attendee.count }.by(-1)
        response.should redirect_to user_path(prim.user)
      end
    end

    describe '#edit' do
      it 'admin can edit any attendee' do
        a = create(:attendee, :year => admin.year)
        get :edit, :id => a.id, :year => a.year
        response.should be_successful
      end
    end

    describe '#update' do
      let(:a) { create(:attendee, :year => admin.year) }

      it 'can update attendee of any user' do
        attrs = accessible_attributes_for(a).merge({:family_name => 'banana'})
        expect { put :update, :id => a.id, :attendee => attrs, :year => a.year
          }.to change { a.reload.family_name }
        a.reload.family_name.should == 'banana'
      end

      it 'can select plan for attendee belonging to someone else' do
        plan = create :plan
        a.plans.should be_empty
        expect { submit_plans_form a, params_for_plan(plan, 1)
          }.to change { a.plans.count }.by(+1)
      end

      it "allows an admin to add activities to any attendee" do
        expect { update_activities(a, activities) }.to \
          change { a.activities.count }.by(activities.length)
      end
    end
  end

  def submit_plans_form(attendee, params)
    params.merge!(:id => attendee.id, :year => attendee.year)
    put :update, params
  end

  def params_for_plan plan, qty
    { "plan_#{plan.id}_qty" => qty }
  end

  def update_activities attendee, activities
    put :update, :id => attendee.id, \
      :attendee => { :activity_id_list => activities.map(&:id) }, \
      :page => 'basics', :year => attendee.year
  end

end
