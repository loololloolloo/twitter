// Front-end behaviour for the classic client. Deliberately jQuery, matching
// the library the original web client used in this era.
$(function () {
  // Account menu in the sidebar opens on hover, as it did on the web client:
  // the popover is a menu, not a page, so pointing at the account row is enough
  // to reveal the switcher, settings and sign out. CSS does the showing; this
  // only keeps aria-expanded honest for screen readers, and mirrors the same
  // state for keyboard users, who get the menu through :focus-within.
  $('.account-menu').each(function () {
    var $menu = $(this);
    var $link = $menu.children('.account-link');

    $menu.on('mouseenter focusin', function () {
      $link.attr('aria-expanded', 'true');
    }).on('mouseleave focusout', function () {
      $link.attr('aria-expanded', 'false');
    });

    // Escape still dismisses it, which matters for the keyboard path.
    $menu.on('keydown', function (e) {
      if (e.key === 'Escape') {
        $menu.removeClass('open');
        $link.attr('aria-expanded', 'false').trigger('blur');
      }
    });

    // Touch devices get no hover, so tapping the row toggles the menu there.
    // The media query keeps this from fighting the hover behaviour on desktop,
    // where the click would otherwise close what the pointer just opened.
    if (!window.matchMedia || !window.matchMedia('(hover: hover)').matches) {
      $link.on('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        var open = !$menu.hasClass('open');

        $('.account-menu').removeClass('open');
        $menu.toggleClass('open', open);
        $link.attr('aria-expanded', open ? 'true' : 'false');
      });

      $('body').on('click', function () {
        $menu.removeClass('open');
        $link.attr('aria-expanded', 'false');
      });
    }
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

  // Alt text belongs with an image, so the field only appears once one is
  // chosen. Hiding it again when the picker is cleared keeps the composer from
  // asking for a description of nothing.
  $(document).on('change', '[data-media-input]', function () {
    var chosen = this.files && this.files.length > 0;
    $(this).closest('form').find('[data-alt-wrap]').prop('hidden', !chosen).toggle(!!chosen);
    // Picking a photo or video clears any GIF that was staged, since a post
    // carries one attachment and leaving both set would silently drop one.
    if (chosen) { clearGif($(this).closest('form')); }
  });

  // The GIF panel. Opening it is purely local: the link is resolved by the
  // server on submit, so the panel never has to reach a third party and a
  // pasted link that cannot be embedded is reported as a normal form error.
  function clearGif($form) {
    $form.find('[data-gif-url]').val('');
    $form.find('[data-gif-url-hidden]').val('');
    $form.find('[data-gif-file]').val('');
    $form.find('[data-gif-note]').prop('hidden', true).text('');
  }

  $(document).on('click', '[data-gif-open]', function () {
    var $panel = $(this).closest('form').find('[data-gif-panel]');
    $panel.prop('hidden', !$panel.prop('hidden'));
    if (!$panel.prop('hidden')) { $panel.find('[data-gif-url]').trigger('focus'); }
  });

  $(document).on('click', '[data-gif-close]', function () {
    $(this).closest('[data-gif-panel]').prop('hidden', true);
  });

  // A link stages itself in the hidden field that is actually submitted.
  // Staging it here rather than reading the text input on submit means the
  // value that reaches the server is the one the reader last confirmed.
  $(document).on('click', '[data-gif-use-link]', function () {
    var $form = $(this).closest('form');
    var value = $.trim($form.find('[data-gif-url]').val());
    var $note = $form.find('[data-gif-note]');
    if (!value) {
      $note.prop('hidden', false).text('Paste a GIF link first.');
      return;
    }
    $form.find('[data-gif-url-hidden]').val(value);
    $form.find('[data-gif-file]').val('');
    $note.prop('hidden', false).text('GIF link added. Post it with your Tweet.');
  });

  // Choosing a GIF file stages nothing: it submits as an ordinary upload, so
  // the link field and its hidden value are cleared to avoid sending both.
  $(document).on('change', '[data-gif-file]', function () {
    var $form = $(this).closest('form');
    var chosen = this.files && this.files.length > 0;
    if (chosen) {
      $form.find('[data-gif-url]').val('');
      $form.find('[data-gif-url-hidden]').val('');
      $form.find('[data-media-input]').val('');
      $form.find('[data-gif-note]').prop('hidden', false).text('GIF file added.');
    } else {
      $form.find('[data-gif-note]').prop('hidden', true).text('');
    }
  });

  // The poll builder. Opening the panel reveals the two starting choices; a
  // choice already typed is kept while the panel is closed, so closing it by
  // accident does not discard the draft.
  $(document).on('click', '[data-poll-open]', function () {
    var $panel = $(this).closest('form').find('[data-poll-panel]');
    $panel.prop('hidden', !$panel.prop('hidden'));
    if (!$panel.prop('hidden')) { $panel.find('.poll-input').first().trigger('focus'); }
  });

  $(document).on('click', '[data-poll-close]', function () {
    $(this).closest('[data-poll-panel]').prop('hidden', true);
  });

  // "Add choice" reveals the next hidden choice, and disappears once all four
  // are shown, since four is the maximum a poll can carry.
  $(document).on('click', '[data-poll-add]', function () {
    var $panel = $(this).closest('[data-poll-panel]');
    var $hidden = $panel.find('[data-poll-choice][hidden]').first();
    if (!$hidden.length) return;
    $hidden.prop('hidden', false).removeAttr('hidden');
    $hidden.find('.poll-input').trigger('focus');
    if (!$panel.find('[data-poll-choice][hidden]').length) { $(this).prop('hidden', true); }
  });

  // The schedule panel. Like the GIF panel, the value is staged: only the
  // hidden field is submitted, and it only carries a value once the writer has
  // pressed Set, so a half-typed date never schedules anything by accident.
  $(document).on('click', '[data-schedule-open]', function () {
    var $panel = $(this).closest('form').find('[data-schedule-panel]');
    $panel.prop('hidden', !$panel.prop('hidden'));
    $(this).attr('aria-expanded', !$panel.prop('hidden'));
    if (!$panel.prop('hidden')) { $panel.find('[data-schedule-input]').trigger('focus'); }
  });

  $(document).on('click', '[data-schedule-close]', function () {
    $(this).closest('[data-schedule-panel]').prop('hidden', true);
  });

  function scheduleFailed($form, message) {
    $form.find('[data-schedule-note]').prop('hidden', false).text(message);
  }

  $(document).on('click', '[data-schedule-set]', function () {
    var $form = $(this).closest('form');
    var raw = $.trim($form.find('[data-schedule-input]').val());
    if (!raw) {
      scheduleFailed($form, 'Choose a date and time first.');
      return;
    }

    var when = new Date(raw.replace(' ', 'T'));
    if (isNaN(when.getTime())) {
      scheduleFailed($form, 'Use the form YYYY-MM-DD HH:MM.');
      return;
    }
    if (when.getTime() <= Date.now()) {
      scheduleFailed($form, 'Pick a time in the future.');
      return;
    }

    $form.find('[data-schedule-hidden]').val(raw);
    $form.find('[data-schedule-note]').prop('hidden', true).text('');
    $form.find('[data-schedule-chip]').prop('hidden', false).text(
      when.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })
    );
    $form.find('.tweet-btn').text('Schedule');
    $form.find('[data-schedule-panel]').prop('hidden', true);
  });

  $(document).on('click', '[data-schedule-clear]', function () {
    var $form = $(this).closest('form');
    $form.find('[data-schedule-hidden]').val('');
    $form.find('[data-schedule-input]').val('');
    $form.find('[data-schedule-chip]').prop('hidden', true).text('');
    $form.find('[data-schedule-note]').prop('hidden', true).text('');
    $form.find('.tweet-btn').text('Tweet');
  });

  // The emoji picker inserts at the caret rather than at the end, which is
  // what the client did: typing around emoji should not move the cursor to
  // the end of the draft. The panel stays open so several can be added.
  $(document).on('click', '[data-emoji-open]', function () {
    var $panel = $(this).closest('form').find('[data-emoji-panel]');
    $panel.prop('hidden', !$panel.prop('hidden'));
  });

  $(document).on('click', '[data-emoji-close]', function () {
    $(this).closest('[data-emoji-panel]').prop('hidden', true);
  });

  $(document).on('click', '.emoji-item', function () {
    var $form = $(this).closest('form');
    var $box = $form.find('.tweet-box');
    if (!$box.length) return;

    var glyph = $(this).data('emoji');
    var el = $box.get(0);
    var start = typeof el.selectionStart === 'number' ? el.selectionStart : null;
    var end = typeof el.selectionEnd === 'number' ? el.selectionEnd : null;

    if (start === null) {
      // No selection support: append, which is still better than dropping it.
      el.value = el.value + glyph;
    } else {
      el.value = el.value.slice(0, start) + glyph + el.value.slice(end);
      el.selectionStart = el.selectionEnd = start + glyph.length;
    }

    // The counter and the draft-length rules both read the value, so the same
    // event the user typing would fire has to be fired here, or the counter
    // goes stale and the Tweet button keeps the wrong enabled state.
    $box.trigger('input');
    el.focus();
  });

  // Copying a permalink. The link is read from the data attribute rather than
  // built in the script, so the address is always the one the server renders.
  $(document).on('click', '[data-copy-link]', function (e) {
    e.preventDefault();
    var url = $(this).data('copy-link');
    if (!url) return;

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(url).then(function () {
        flash('Copied to clipboard', 'ok');
      }, function () {
        flash(url, 'ok');
      });
    } else {
      flash(url, 'ok');
    }
  });

  // The per-post overflow menu closes when a click lands outside it, which is
  // what <details> does not do on its own.
  $(document).on('click', function (e) {
    if ($(e.target).closest('.tweet-menu').length) return;
    $('.tweet-menu[open]').removeAttr('open');
  });

  // Clicking a reply link focuses the reply box on a tweet page.
  $('.open-reply').on('click', function (e) {
    e.preventDefault();
    $('.composer textarea').focus();
  });

  // Favourite, like and retweet are toggles, so they are answered in place
  // instead of reloading the page and throwing the reader back to the top of
  // the timeline. The form is still submitted normally if the script is
  // unavailable, which is why the buttons live inside real forms.
  $(document).on('submit', 'form.js-like, form.js-fav, form.js-retweet, form.js-bookmark', function (e) {
    var $form = $(this);
    if ($form.data('busy')) return false;

    e.preventDefault();
    $form.data('busy', true);

    // All four controls are toggles. The retweet route flips state on a single
    // POST; likes, favourites and bookmarks add on POST and remove on DELETE,
    // so the request is built from the form's own state.
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
    } else if ($form.hasClass('js-bookmark')) {
      var bookmarked = !!$form.data('bookmarked');
      url = bookmarked ? $form.data('unsave-url') : $form.data('save-url');
      method = bookmarked ? 'delete' : 'post';
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

      // Each control is painted only when the answer actually carried its
      // figures. A bookmark toggle answers with the saved state alone, and
      // painting counts from that would blank the other controls.
      if (data.favourite_count_label !== undefined) {
        paintCount($row.find('.act-fav'), data.favourite_count_label, data.favourited, 'Favorited');
        $row.find('form.js-fav').data('favourited', !!data.favourited);
      }
      if (data.like_count_label !== undefined) {
        paintCount($row.find('.act-heart'), data.like_count_label, data.liked, 'Liked');
        $row.find('form.js-like').data('liked', !!data.liked);
      }
      if (data.retweet_count_label !== undefined) {
        paintCount($row.find('.act-rt'), data.retweet_count_label, data.retweeted, 'Retweeted');
      }
      if (data.reply_count_label !== undefined) {
        paintCount($row.find('.act-reply'), data.reply_count_label, false, null);
      }

      // Bookmarking has no count, only a state, so it is painted separately.
      if (data.bookmarked !== undefined) {
        var $save = $row.find('.act-save');
        $save.toggleClass('saved', !!data.bookmarked);
        $save.attr('title', data.bookmarked ? 'Remove from saved posts' : 'Save post');
        $row.find('form.js-bookmark').data('bookmarked', !!data.bookmarked);
      }
    });

    // Writes refreshed engagement onto every row for the given tweets, keyed by
  // id. Shared by the timeline poll and the permalink poll.
  //
  // A control the reader has already used is skipped: those show a word
  // ("Liked") instead of a number and carry the active class, and repainting
  // them from a count would clear the reader's own reaction. Everything else is
  // safe to update in place.
  function paintCounts(counts) {
    if (!counts) return;

    var fresh = function ($el) {
      return $el.length && !$el.hasClass('hearted') && !$el.hasClass('faved') &&
             !$el.hasClass('rt-active');
    };

    for (var id in counts) {
      if (!Object.prototype.hasOwnProperty.call(counts, id)) continue;

      var data = counts[id];
      $('[data-tweet="' + id + '"]').each(function () {
        var $row = $(this);
        var $fav = $row.find('.act-fav');
        var $like = $row.find('.act-heart');
        var $rt = $row.find('.act-rt');
        var $reply = $row.find('.act-reply');

        if (fresh($fav)) paintCount($fav, data.favourite_count_label, false, null);
        if (fresh($like)) paintCount($like, data.like_count_label, false, null);
        if (fresh($rt)) paintCount($rt, data.retweet_count_label, false, null);
        if (fresh($reply)) paintCount($reply, data.reply_count_label, false, null);
      });
    }
  }

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
    // A Top-ranked stream still polls, but only so its counters stay current;
    // queuing arriving entries there would put them out of rank order.
    var queuesNew = $timeline.data('show') !== 'top';
    var pending = {};
    var pendingCount = 0;

    // Every row already rendered, so a poll can never re-queue a tweet that is
    // on the page - which would otherwise show up twice when revealed.
    var seen = {};
    $timeline.find('[data-tweet]').each(function () {
      seen[$(this).data('tweet')] = true;
    });

    var poll = function () {
      // Ids of the posts currently on the page, so the same poll that fetches
      // new entries also brings back the current engagement for the ones
      // already rendered. Without this the counters froze at whatever they
      // were when the page was drawn, which is what made them look like they
      // stopped climbing.
      var ids = $timeline.find('[data-tweet]').map(function () {
        return $(this).data('tweet');
      }).get().join(',');

      $.getJSON(feedUrl, { after: newest, ids: ids })
        .done(function (data) {
          if (!data) return;

          paintCounts(data.counts);

          if (!queuesNew) return;
          if (!data.count || !data.html) return;

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

  // A permalink stays current the same way the timeline does. The focused post
  // and its replies are all on the page, so their ids go in one request and the
  // refreshed figures are written back over the rows already there.
  var $permalink = $('#permalink');
  if ($permalink.length && $permalink.data('stats-url')) {
    var statsUrl = $permalink.data('stats-url');

    var refreshStats = function () {
      var ids = $permalink.find('[data-tweet]').map(function () {
        return $(this).data('tweet');
      }).get().join(',');

      $.getJSON(statsUrl, { ids: ids })
        .done(function (data) {
          if (!data || data.id === undefined) return;

          var counts = {};
          counts[data.id] = data;
          (data.replies || []).forEach(function (reply) {
            counts[reply.id] = reply;
          });

          paintCounts(counts);
        });
    };

    setInterval(refreshStats, 5000);
  }
});
// Bulk selection on the accounts list. The form must never look ready to run
// with nothing selected, so the count and the submit button are driven from the
// checkboxes. Progressive enhancement only: the run itself is refused in the
// controller when the selection is empty, whatever the browser sends.
$(function () {
  var $form = $('#bulk-form');
  if (!$form.length) return;

  var $counts = $form.find('.bulk-pick');
  var $all = $('#bulk-all');
  var $count = $('#bulk-count');
  var $tag = $('#bulk-tag');
  var $action = $('#bulk-action');
  var $submit = $form.find('.bulk-bar button[type="submit"]');

  // The tag picker only applies to the two tag actions, so it stays hidden for
  // everything else rather than inviting a tag that would be ignored.
  var syncTag = function () {
    $tag.toggle($action.val() === 'tag_on' || $action.val() === 'tag_off');
  };

  var sync = function () {
    var picked = $counts.filter(':checked').length;
    $count.text(picked === 0 ? 'No accounts selected'
                             : picked + (picked === 1 ? ' account selected' : ' accounts selected'));
    $submit.prop('disabled', picked === 0);
    $all.prop('checked', picked > 0 && picked === $counts.length);
  };

  $all.on('change', function () { $counts.prop('checked', this.checked); sync(); });
  $counts.on('change', sync);
  $action.on('change', syncTag);

  syncTag();
  sync();
});
