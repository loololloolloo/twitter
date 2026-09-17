// Front-end behaviour for the classic client. Deliberately jQuery, matching
// the library the original web client used in this era.
$(function () {
  // Account menu in the top bar opens on click and closes on an outside click.
  $('.account-menu').on('click', function (e) {
    e.stopPropagation();
    $(this).toggleClass('open');
  });

  $('body').on('click', function () {
    $('.account-menu').removeClass('open');
  });

  // Character counter on the composer, turning red past the limit.
  var $composer = $('.composer textarea');
  if ($composer.length) {
    var limit = parseInt($composer.attr('maxlength'), 10) || 140;
    var $counter = $('.composer .counter');

    var update = function () {
      var remaining = limit - $composer.val().length;
      $counter.text(remaining);
      $counter.toggleClass('over', remaining < 0);
      $composer.closest('form').find('.btn-primary')
        .prop('disabled', remaining < 0 || $composer.val().trim() === '');
    };

    $composer.on('input', update);
    update();

    // Auto-growing the composer, as the classic client did.
    $composer.on('input', function () {
      this.style.height = 'auto';
      this.style.height = Math.min(this.scrollHeight, 300) + 'px';
    });
  }

  // Clicking a reply link focuses the reply box on a tweet page.
  $('.open-reply').on('click', function (e) {
    e.preventDefault();
    $('.composer textarea').focus();
  });

  // Favourite, like and retweet are toggles, so they are answered in place
  // instead of reloading the page and throwing the reader back to the top of
  // the timeline. The form is still submitted normally if the script is
  // unavailable, which is why the buttons live inside real forms.
  $(document).on('submit', 'form.js-like, form.js-fav, form.js-retweet', function (e) {
    var $form = $(this);
    if ($form.data('busy')) return false;

    e.preventDefault();
    $form.data('busy', true);

    // All three controls are toggles. The retweet route flips state on a single
    // POST; likes and favourites add on POST and remove on DELETE, so the
    // request is built from the form's own state.
    var url = $form.attr('action');
    var method = 'post';

    if ($form.hasClass('js-like')) {
      var liked = !!$form.data('liked');
      url = liked ? $form.data('unlike-url') : $form.data('like-url');
      method = liked ? 'delete' : 'post';
    } else if ($form.hasClass('js-fav')) {
      var favourited = !!$form.data('favourited');
      url = favourited ? $form.data('unfav-url') : $form.data('fav-url');
      method = favourited ? 'delete' : 'post';
    }

    $.ajax({
      url: url,
      method: method,
      dataType: 'json',
      headers: { 'X-CSRF-Token': $('meta[name="csrf-token"]').attr('content') }
    })
      .done(function (data) {
        if (data && data.error) {
          flash(data.error, 'error');
          return;
        }
        paint(data);
      })
      .fail(function () {
        // Anything unexpected falls back to the full submit, so the action is
        // never silently swallowed.
        $form.removeData('busy');
        $form[0].submit();
      })
      .always(function () {
        $form.removeData('busy');
      });

    return false;
  });

  // Repaints every copy of a tweet's engagement row from the server's answer.
  // A tweet appears in more than one place at once (timeline and, after a
  // retweet, its author's feed), so the update is applied by tweet id rather
  // than to the one row that was clicked.
  function paint(data) {
    if (!data || data.id === undefined) return;

    $('[data-tweet="' + data.id + '"]').each(function () {
      var $row = $(this);
      paintCount($row.find('.act-fav'), data.favourite_count_label, data.favourited, 'Favorited');
      paintCount($row.find('.act-heart'), data.like_count_label, data.liked, 'Liked');
      paintCount($row.find('.act-rt'), data.retweet_count_label, data.retweeted, 'Retweeted');
      paintCount($row.find('.act-reply'), data.reply_count_label, false, null);

      // The forms carry the state too, so the next click on either control
      // toggles in the right direction rather than repeating the last request.
      $row.find('form.js-like').data('liked', !!data.liked);
      $row.find('form.js-fav').data('favourited', !!data.favourited);
    });

    // The permalink page's count line is a separate block from the buttons.
    $('.permalink-tweet[data-tweet="' + data.id + '"] .tweet-stats').each(function () {
      var $stats = $(this);
      var $spans = $stats.children();
      var figures = [ data.retweet_count_label, data.favourite_count_label,
                      data.like_count_label, data.reply_count_label ];

      $spans.each(function (i) {
        if (figures[i] === undefined) return;
        $(this).find('strong').text(figures[i]);
      });
    });
  }

  function paintCount($el, label, active, activeLabel) {
    if (!$el.length) return;

    $el.toggleClass('faved', $el.hasClass('act-fav') && !!active);
    $el.toggleClass('hearted', $el.hasClass('act-heart') && !!active);
    $el.toggleClass('rt-active', $el.hasClass('act-rt') && !!active);

    // The star and heart swap between outline and solid, matching the state.
    if ($el.hasClass('act-fav')) swapIcon($el, active ? 'star-solid' : 'star-regular');
    if ($el.hasClass('act-heart')) swapIcon($el, active ? 'heart-twitter-solid' : 'heart-twitter');

    var $count = $el.find('.act-count');
    var text = active && activeLabel ? activeLabel : label;

    if (!text || text === '0') {
      $count.remove();
      return;
    }
    if ($count.length) {
      $count.text(text);
    } else {
      $el.append($('<span class="act-count"></span>').text(text));
    }
  }

  // Swaps an SVG in place by name. The markup is fetched once per name and
  // cached, so a toggled button does not re-request its icon.
  var iconCache = {};
  function swapIcon($el, name) {
    var $current = $el.find('svg.ico');
    if (!$current.length || $current.data('icon') === name) return;

    if (iconCache[name]) {
      $current.replaceWith(iconCache[name].clone());
      $el.find('svg.ico').data('icon', name);
      return;
    }

    $.get('/assets/icons/' + name + '.svg').done(function (svg) {
      var $svg = $(svg);
      $svg.addClass('ico').data('icon', name);
      iconCache[name] = $svg;
      $el.find('svg.ico').replaceWith($svg.clone());
    });
  }

  // A short-lived message in the same place the server-rendered flashes land.
  function flash(message, kind) {
    var $wrap = $('.flash-wrap');
    if (!$wrap.length) return;

    var $note = $('<div class="flash"></div>').addClass(kind === 'error' ? 'flash-alert' : 'flash-notice').text(message);
    $wrap.append($note);
    setTimeout(function () { $note.fadeOut(300, function () { $(this).remove(); }); }, 3000);
  }

  // The home timeline keeps itself current while it is open. New entries are
  // collected in the background and announced with a "New tweets" bar rather
  // than being injected mid-read, which is what the classic client did.
  var $timeline = $('#timeline');
  if ($timeline.length && $timeline.data('feed-url')) {
    var feedUrl = $timeline.data('feed-url');
    var newest = $timeline.data('newest') || '';
    var pending = {};
    var pendingCount = 0;

    // Every row already rendered, so a poll can never re-queue a tweet that is
    // on the page - which would otherwise show up twice when revealed.
    var seen = {};
    $timeline.find('[data-tweet]').each(function () {
      seen[$(this).data('tweet')] = true;
    });

    var poll = function () {
      $.getJSON(feedUrl, { after: newest })
        .done(function (data) {
          if (!data || !data.count || !data.html) return;

          var $rows = $('<div>').html(data.html).children();
          var added = 0;

          $rows.each(function () {
            var id = $(this).data('tweet');

            if (id === undefined || seen[id] || pending[id]) return;

            pending[id] = this.outerHTML;
            added++;
          });

          if (!added) return;

          pendingCount += added;
          newest = data.newest || newest;
          $('#new-tweets-link').text(pendingCount + (pendingCount === 1 ? ' new tweet' : ' new tweets'));
          $('#new-tweets').prop('hidden', false);
        });
    };

    // Revealing the new entries is a deliberate click, so the reader is never
    // moved while scrolling through the timeline.
    $('#new-tweets-link').on('click', function (e) {
      e.preventDefault();
      if (!pendingCount) return;

      var html = '';
      for (var id in pending) {
        if (!Object.prototype.hasOwnProperty.call(pending, id)) continue;
        seen[id] = true;
        html += pending[id];
      }

      $timeline.prepend(html);
      $timeline.find('.empty').remove();
      pending = {};
      pendingCount = 0;
      $('#new-tweets').prop('hidden', true);
      $(document).scrollTop(0);
    });

    setInterval(poll, 5000);
  }
});