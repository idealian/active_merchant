require 'test_helper'

class RemoteSecurePayAuTest < Test::Unit::TestCase
  
  def setup
    @gateway = SecurePayAuGateway.new(fixtures(:secure_pay_au))
    
    @amount = 100
    @credit_card = credit_card('4444333322221111')

    @options = { 
      :order_id => '1',
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end

  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
  end
  
  def test_unsuccessful_purchase
    @credit_card.year = '2005'
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'CARD EXPIRED', response.message
  end
  
  def test_invalid_login
    gateway = SecurePayAuGateway.new(
                :login => '',
                :password => ''
              )
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal "Invalid merchant ID", response.message
  end
  
  def test_successful_create_recurring_payment
    client_id = generate_unique_id[0...10]

    response = @gateway.recurring(999, @credit_card, 
      :order_id => '1',
      :billing_address => address,
      :description => 'Store Purchase',
      :profile_id => client_id,
      :periodicity => :monthly,
      :payments => 20
    )
    
    assert_success response
  end
  
  def test_successful_cancel_recurring_payment
    client_id = generate_unique_id[0...10]
    
    @gateway.recurring(123456, @credit_card, 
      :profile_id => client_id,
      :periodicity => :monthly,
      :payments => 20
    )
    
    response = @gateway.cancel_recurring(client_id)
    
    assert_success response
  end

end
