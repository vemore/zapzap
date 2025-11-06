// =============================================================================
// ERROR HANDLING
// =============================================================================

/**
 * Show error message to user
 * @param {string} message - Error message
 * @param {number} duration - Duration to show message (ms)
 */
function showError(message, duration) {
    duration = duration || 3000;

    // Remove existing error toasts
    $('.error-toast').remove();

    // Create error toast
    var $error = $('<div class="error-toast">')
        .text(message)
        .css({
            position: 'fixed',
            top: '20px',
            right: '20px',
            background: '#f44336',
            color: 'white',
            padding: '15px 20px',
            borderRadius: '4px',
            boxShadow: '0 2px 5px rgba(0,0,0,0.2)',
            zIndex: 10000,
            fontFamily: 'Arial, sans-serif',
            fontSize: '14px',
            maxWidth: '300px'
        })
        .appendTo('body');

    // Auto-remove after duration
    setTimeout(function() {
        $error.fadeOut(300, function() {
            $(this).remove();
        });
    }, duration);
}

/**
 * Handle AJAX errors with user-friendly messages
 * @param {object} jqXHR - jQuery XHR object
 * @param {string} textStatus - Status text
 * @param {string} errorThrown - Error description
 * @param {string} context - Context of the error for logging
 */
function handleAjaxError(jqXHR, textStatus, errorThrown, context) {
    console.error('API call failed:', {
        context: context,
        status: jqXHR.status,
        statusText: jqXHR.statusText,
        textStatus: textStatus,
        error: errorThrown,
        response: jqXHR.responseJSON
    });

    // Extract error message from response
    var errorMessage = 'Network error';

    if (jqXHR.responseJSON && jqXHR.responseJSON.error) {
        errorMessage = jqXHR.responseJSON.error;
    } else if (jqXHR.status === 403) {
        errorMessage = 'Not your turn or invalid action';
    } else if (jqXHR.status === 400) {
        errorMessage = 'Invalid request';
    } else if (jqXHR.status === 404) {
        errorMessage = 'Endpoint not found';
    } else if (jqXHR.status >= 500) {
        errorMessage = 'Server error';
    } else if (textStatus === 'timeout') {
        errorMessage = 'Request timed out';
    } else if (textStatus === 'abort') {
        errorMessage = 'Request aborted';
    }

    showError(errorMessage);

    // Retry logic for server errors
    if (jqXHR.status >= 500 || textStatus === 'timeout') {
        console.log('Retrying in 2 seconds...');
        // Note: Retry logic would go here if needed
    }
}

// =============================================================================
// GAME STATE FUNCTIONS
// =============================================================================

function build_player_table($container) {
    $.getJSON('/party')
        .done(function( data ) {
            var $table = document.createElement('table');
            $table.id = "player_table"
            $container.appendChild($table);

            for (i=0; i<data.players.length; i++) {
                $table.insertRow($table.rows.length);
                $table.rows[i].insertCell($table.rows[i].cells.length);
                $table.rows[i].insertCell($table.rows[i].cells.length);
                $table.rows[i].cells[0].textContent = data.players[i].name;
                $table.rows[i].cells[1].textContent = data.players[i].nb_cards;
            }
        })
        .fail(function(jqXHR, textStatus, errorThrown) {
            handleAjaxError(jqXHR, textStatus, errorThrown, 'build_player_table');
        });
}

function update_player_table(data) {
    var $table = document.getElementById('player_table');
    if ($table!=undefined) {
        for (i=0; i<data.players.length; i++) {
            $table.rows[i].cells[0].textContent = data.players[i].name;
            $table.rows[i].cells[1].textContent = data.players[i].nb_cards;

            if (data.current_turn%data.nb_players==i)
                $table.rows[i].classList.add("current_turn");
            else
                $table.rows[i].classList.remove("current_turn");
        }
    }
}

function update_common_deck(data) {
    var index_cards_back = 0;
    var nb_last_cards_played = 0;
    var nb_cards_played = 0;
    var last_of_deck = null;
    // Update deck, play, and last play
    for (var i = 54; i >= 0; i--) {
        var card = game_deck.cards[i];
        card.$el.dataset.id = i;
        if (data.last_cards_played.includes(i)){
            card.setSide('front');
            card.x = 40 + nb_last_cards_played*20;
            card.y = 0;
            card.$el.style.display = '';
            card.$el.style[Deck.prefix('transform')] = Deck.translate(card.x+'px', '0');
            nb_last_cards_played += 1;
            //console.log("Card "+i+" : front");
        } else if (data.cards_played.includes(i)) {
            card.setSide('front');
            card.x = 40 + nb_cards_played*20;
            card.y = 90;
            card.$el.style.display = '';
            card.$el.style[Deck.prefix('transform')] = Deck.translate(card.x+'px', card.y+'px');
            nb_cards_played += 1;
        } else if (index_cards_back<data.card_in_deck) {
            card.setSide('back');
            card.x = -40 -index_cards_back/2;
            card.y = -index_cards_back/2;
            card.$el.style.display = '';
            card.$el.style[Deck.prefix('transform')] = Deck.translate(card.x+'px', card.y+'px');
            index_cards_back += 1;
            last_of_deck = card;
            card.$el.dataset.id = -1;
            //console.log("Card "+i+" : back");
        } else {
            card.unmount();
            //console.log("Card "+i+" : remove");
        }
    }

    last_of_deck.$el.addEventListener("click", function(){
        elements = game_container.getElementsByClassName("draw_select");
        while(elements.length > 0){
            elements[0].classList.remove('draw_select');
        }
        last_of_deck.$el.classList.add("draw_select");
    });

    data.last_cards_played.forEach( card_id => {
        game_deck.cards[card_id].$el.addEventListener("click", function(){
            elements = game_container.getElementsByClassName("draw_select");
            while(elements.length > 0){
                elements[0].classList.remove('draw_select');
            }
            game_deck.cards[card_id].$el.classList.add("draw_select");
        });
    });
}

function show_players_hand(data) {
    var show_cards = [];
    for (i=0; i<data.players.length; i++) {
        for (j=0; j<data.players[i].hand.length; j++) {
            var card = game_deck.cards[data.players[i].hand[j]];
            card.setSide('front');
            card.x = 160*i - 80*data.players.length + 20*j;
            card.y = 0;
            card.$el.style.display = '';
            card.$el.style[Deck.prefix('transform')] = Deck.translate(card.x+'px', card.y+'px');

            show_cards.push(data.players[i].hand[j]);
        }
        var $message = document.createElement('div')
        $message.classList.add('player_name')
        $message.textContent = data.players[i].name + ' : ' + data.players[i].score;
        $message.style[Deck.prefix('transform')] = Deck.translate(160*i -40 - 80*data.players.length+'px', 60+'px');
        game_container.appendChild($message)
    }
    console.log("Show cards : "+show_cards);
    for (var i = 54; i >= 0; i--) {
        if (!show_cards.includes(i)) {
            //game_deck.cards[i].$el.style.display = 'none';
            game_deck.cards[i].unmount();
            console.log("Hide card "+i);
        }
    }
}

var game_deck = undefined;
var game_container;
var hand_deck;
var hand_container;
var hand_cards_id;
var player_id;

function build_game($container) {
    game_container = $container;
    return update_game();
}

function update_game() {
    console.log("update_game");
    if (game_deck!=undefined)
        game_deck.unmount();
    game_deck = Deck(true);

    $.getJSON('/party')
        .done(function( data ) {
            // Update deck, play, and last play
            if (data.action=="zapzap") {
                show_players_hand(data);
            } else {
                update_common_deck(data);
            }

            // Update table
            update_player_table(data);

            // disable all buttons
            $(':button').prop('disabled', true);

            // Enable Buttons for current player
            if (data.current_turn%data.nb_players==player_id) {
                switch(data.action) {
                    case "draw" : $play.disabled = ''; $zapzap.disabled = ''; break;
                    case "play" : $draw.disabled = ''; break;
                }
            }
        })
        .fail(function(jqXHR, textStatus, errorThrown) {
            handleAjaxError(jqXHR, textStatus, errorThrown, 'update_game');
        });
    game_deck.mount(game_container);



    return game_deck;
}



function update_player_hand(cards_id) {
    if (hand_deck!=undefined) {
        hand_deck.unmount();
    }
    hand_deck = Deck(true);
    hand_deck.mount(hand_container);
    hand_cards_id = Array.from(cards_id);
    for (var i = 54; i >= 0; i--) {
        var card = hand_deck.cards[i];
        if (cards_id.includes(i)){
            card.setSide('front');
            card.$el.dataset.id = i;
        }
        else {
            card.unmount();
            hand_deck.cards.splice(i, 1);
        }
    }
    hand_deck.cards.forEach(function (card, i) {
        card.$el.addEventListener("click", function(){
            card.$el.classList.toggle("selected");
        });
    });

    hand_deck.fan();
}

function build_player_hand($container, id_player) {
    //hand_deck = Deck(true);
    hand_container = $container;
    player_id = id_player;

    $.getJSON('/player/'+id_player+'/hand')
        .done(function( data ) {
            update_player_hand(data);
            //deck.sort();
        })
        .fail(function(jqXHR, textStatus, errorThrown) {
            handleAjaxError(jqXHR, textStatus, errorThrown, 'build_player_hand');
        });
    return hand_deck;
}

var $draw = null;
var $play = null;
var $bysuit = null;
var $fan = null;
var $zapzap = null;
var $update = null;

function build_topbar($topbar) {
    $draw = document.createElement('button')
    $play = document.createElement('button')
    $bysuit = document.createElement('button')
    $fan = document.createElement('button')
    $zapzap = document.createElement('button')
    $update = document.createElement('button')

    $play.textContent = 'Play'
    $draw.textContent = 'Draw'

    $bysuit.textContent = 'By suit'
    $fan.textContent = 'Fan'

    $zapzap.textContent = 'ZapZap'
    $update.textContent = 'Update'

    $topbar.appendChild($update)
    $topbar.appendChild($play)
    $topbar.appendChild($bysuit)
    $topbar.appendChild($fan)
    $topbar.appendChild($zapzap)
    $topbar.appendChild($draw)

    const evtSource = new EventSource('/suscribeupdate');
    evtSource.addEventListener('event', function(evt) {
        update_game();
    },false);


    $bysuit.addEventListener('click', function () {
        hand_deck.sort(true) // sort reversed
        hand_deck.bysuit()
    });

    $fan.addEventListener('click', function () {
        hand_deck.fan()
    });



    $update.addEventListener('click', function () {
        update_game()
    });

    $play.addEventListener('click', function () {
        player_hand = document.getElementById("player_hand")
        $cards = player_hand.getElementsByClassName("selected");
        var play = [];
        for (let $card of $cards) {
            play.push($card.dataset.id);
        }
        console.log("Play : "+ play);

        $.getJSON('/player/'+ player_id + '/play', { cards: play })
        .done(function( json ) {
            // Handle both old format (array) and new format (object with hand)
            const hand = json.hand || json;
            update_player_hand(hand);
            //update_game();
        })
        .fail(function(jqXHR, textStatus, errorThrown) {
            handleAjaxError(jqXHR, textStatus, errorThrown, 'play_cards');
        });
    });

    $draw.addEventListener('click', function () {
        elements = game_container.getElementsByClassName("draw_select");
        console.log("elements : "+ elements);
        $.getJSON('/player/'+ player_id + '/draw', { card: elements[0].dataset.id })
        .done(function( json ) {
            console.log("Draw : "+ json.draw);
            update_player_hand(json.hand);
            //update_game();
        })
        .fail(function(jqXHR, textStatus, errorThrown) {
            handleAjaxError(jqXHR, textStatus, errorThrown, 'draw_card');
        });
    });

    $zapzap.addEventListener('click', function () {
        elements = game_container.getElementsByClassName("draw_select");
        $.getJSON('/player/'+ player_id + '/zapzap', {})
        .done(function( json ) {
            console.log("ZapZap called successfully");
            // Game state will update via SSE event
            //update_player_hand(json.hand);
            //update_game();
        })
        .fail(function(jqXHR, textStatus, errorThrown) {
            handleAjaxError(jqXHR, textStatus, errorThrown, 'zapzap');
        });
    });


}