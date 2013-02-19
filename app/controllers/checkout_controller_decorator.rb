Spree::CheckoutController.class_eval do
    skip_before_filter :verify_authenticity_token, :only => [:dps_callback]
    skip_before_filter :load_order, :only => :px_pay_callback
    before_filter :before_payment_without_px_pay_redirection_if_needed, :only => [:update]

    # Handles the response from PxPay (success or failure) and updates the
    # relevant Payment record.
    def px_pay_callback
        response = Pxpay::Response.new(params).response.to_hash

        payment = Spree::Payment.find(response[:merchant_reference])

        if payment then
            if response[:success] == '1'
                payment.started_processing
                payment.response_code = response[:auth_code]
                payment.save
                payment.complete
                @order = payment.order
                @order.next

                state_callback(:after)
                if @order.state == "complete" || @order.completed?
                    state_callback(:before)
                    flash.notice = t(:order_processed_successfully)
                    flash[:commerce_tracking] = "nothing special"
                    redirect_to completion_route
                else
                    respond_with(@order, :location => checkout_state_path(@order.state))
                end
            else
                payment.void
                redirect_to cart_path, :notice => 'Your credit card details were declined. Please check your details and try again.'
            end
        else
            # Bad Payment!
            raise Spree::Core::GatewayError, "Unknown merchant_reference: #{response[:merchant_reference]}"
        end
    end

    private

    # Must skip validation as steps don't entirely match up with standard checkout process
    def skip_state_validation?
        true
    end

    def before_payment_without_px_pay_redirection_if_needed
        return unless (params[:state] == "payment")
        return unless params[:order][:payments_attributes]

        if @order.update_attributes(object_params)
            fire_event('spree.checkout.update')
            # Not sure what is happening below - I've commented out - but need to look into coupon codes
            #render :edit and return unless apply_coupon_code
        end

        load_order
        if not @order.errors.empty?
            render :edit and return
        end

        payment_method = Spree::PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])

        if payment_method.kind_of?(Spree::Gateway::PxPay)
            redirect_to px_pay_gateway.url(@order, request)
        end

    end

    def px_pay_gateway
        @order.available_payment_methods.find { |x| x.is_a?(Spree::Gateway::PxPay) }
    end
end
