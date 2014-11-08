(function(window,document,$,undefined){
  $(document).ready(function(){
    
    var $total_amount = $('#total_amount');
    
    $('.auto-title input').example(function(){
      return this.title;
    });
    
    $('#add-one-more').click(function(){
      var nextNum = $('.service-count').length;
      var $services_auto_total = $('#services-clone').find('.auto-total');
      if($services_auto_total && $services_auto_total.attr('value') == ''){
        $services_auto_total.attr('value', (0).toFixed(2));
      }
      var $clone = $('#services-clone').clone();
      $clone.attr('id', $clone.attr('id')+'-'+Math.random());
      $clone.find('.delete').show();
      $clone.find('.service_id').attr('value','');
      $clone.find('input.update-count').each(function(){ this.name = this.name.replace('0',nextNum); });
      $clone.appendTo('#services-container');
      calculateTotal();
    });
    
    $('.delete').live('click', function(){
      var $parentRow = $(this).parent().parent();
      var deleteId = $parentRow.find('.service_id').attr('value');
      if(deleteId != ''){ 
        var del = $('<input type="hidden" name="invoice[delete_services][]" value="' + deleteId + '" />');
        del.appendTo($parentRow.parent());
      }
      $parentRow.remove();
      calculateTotal();
    });

    $('.auto-qty').live('keyup', function(){
      calculateTotal();
    }).live('keydown', function(e){
      return allowNumbers(e);
    });
    
    $('.auto-total').live('keyup', function(){
      calculateTotal();
    }).live('keydown', function(e){
      return allowNumbers(e);
    }).live('blur', function(){
      $this = $(this);
      var total = parseFloat(($this.attr('value') ? $this.attr('value') : 0));
      if(isNaN(total)){
        total = 0;
      }
      $this.attr('value', total.toFixed(2));
    });
    
    function allowNumbers(e){
      var numbers = '1234567890';
      var k = document.all ? parseInt(e.keyCode) : parseInt(e.which);
      if( 
        k == 8 // BACKSPACE
        || k == 9 // TAB
        || k == 39 // RIGHT ARROW
        || k == 37 // LEFT ARROW
      ){
        return true;
      }
      return (numbers.indexOf(String.fromCharCode(k))!=-1);
      return false;
    }
    
    function calculateTotal(){      
      $('.auto-total-added').removeClass('auto-total-added');
      $total_amount.attr('value', getTotals());
    }
    
    function getTotals(){
      var total = 0.00;
      $('.auto-total').not('auto-total-added').each(function(){
        var $this = $(this);
        var $parentRow = $this.parent().parent();
        var qty = parseFloat($parentRow.find('.auto-qty').attr('value'));
        var add_to_total = parseFloat($this.attr('value'));
        if(add_to_total != NaN){
          total += (add_to_total*qty);
        }
        $this.addClass('auto-total-added');
      });
      if(isNaN(total)){
        total = 0;
      }
      return total.toFixed(2);
    }
    
  });
})(this,this.document,jQuery);