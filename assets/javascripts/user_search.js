// Global state for cleanup
let userSearchState = {
  initialized: false,
  listeners: [],
  searchTimeout: null,
  currentRequest: null,
  fieldMappings: null,
  currentSearchQuery: '',
  currentOffset: 0,
  hasMore: false,
  isLoadingMore: false,
  selectedType: 'Employee' // Default to Employee
};

function initializeUserSearch() {
  const searchWidget = document.getElementById('user-search-widget');
  const searchInput = document.getElementById('user-search-input');
  const resultsContainer = document.getElementById('user-search-results');
  const resultsList = document.getElementById('user-results-list');
  const loadingIndicator = document.getElementById('user-search-loading');
  const errorContainer = document.getElementById('user-search-error');
  const typeRadios = document.querySelectorAll('input[name="user-type"]');

  if (!searchInput || !searchWidget) {
    console.log('User search widget not found - exiting');
    return; // Exit if widget not present
  }

  // Get project_id from data attribute
  const projectId = searchWidget.dataset.projectId;
  console.log('User search widget initialized with project_id:', projectId);
  if (!projectId) {
    console.error('No project_id found on user search widget - data-project-id attribute is missing');
    return;
  }

  // Clean up previous initialization
  cleanupUserSearch();

  // Reset state
  userSearchState.searchTimeout = null;
  userSearchState.currentRequest = null;
  userSearchState.fieldMappings = null;
  userSearchState.currentSearchQuery = '';
  userSearchState.currentOffset = 0;
  userSearchState.hasMore = false;
  userSearchState.isLoadingMore = false;
  userSearchState.selectedType = 'Employee'; // Default to Employee
  userSearchState.initialized = true;

  // Load field mappings on initialization
  loadFieldMappings();

  // Update placeholder based on selected type
  updatePlaceholder();

  // Type selector change handler
  typeRadios.forEach(radio => {
    const typeChangeHandler = function() {
      userSearchState.selectedType = this.value;
      console.log('User type changed to:', userSearchState.selectedType);
      updatePlaceholder();
      hideResults();
      hideError();
      // Clear search input and results when type changes
      searchInput.value = '';
    };
    radio.addEventListener('change', typeChangeHandler);
    userSearchState.listeners.push({ element: radio, event: 'change', handler: typeChangeHandler });
  });

  const inputHandler = function() {
    const query = this.value.trim();

    // Clear any existing timeout
    if (userSearchState.searchTimeout) {
      clearTimeout(userSearchState.searchTimeout);
    }

    // Cancel any existing request
    if (userSearchState.currentRequest) {
      userSearchState.currentRequest.abort();
      userSearchState.currentRequest = null;
    }

    // Hide results if query is too short
    if (query.length < 2) {
      hideResults();
      return;
    }

    // Debounce search requests
    userSearchState.searchTimeout = setTimeout(() => {
      performSearch(query);
    }, 300);
  };
  searchInput.addEventListener('input', inputHandler);
  userSearchState.listeners.push({ element: searchInput, event: 'input', handler: inputHandler });

  const keydownHandler = function(e) {
    if (e.key === 'Escape') {
      hideResults();
      this.blur();
    }
  };
  searchInput.addEventListener('keydown', keydownHandler);
  userSearchState.listeners.push({ element: searchInput, event: 'keydown', handler: keydownHandler });

  // Hide results when clicking outside
  const clickHandler = function(e) {
    if (!e.target.closest('.user-search-widget')) {
      hideResults();
    }
  };
  document.addEventListener('click', clickHandler);
  userSearchState.listeners.push({ element: document, event: 'click', handler: clickHandler });

  // Add scroll listener for infinite scroll
  const scrollHandler = function() {
    if (userSearchState.isLoadingMore || !userSearchState.hasMore) return;

    const scrollTop = this.scrollTop;
    const scrollHeight = this.scrollHeight;
    const clientHeight = this.clientHeight;

    // Load more when scrolled to 80% of the content
    if (scrollTop + clientHeight >= scrollHeight * 0.8) {
      loadMoreResults();
    }
  };
  resultsContainer.addEventListener('scroll', scrollHandler);
  userSearchState.listeners.push({ element: resultsContainer, event: 'scroll', handler: scrollHandler });

  function updatePlaceholder() {
    const searchInput = document.getElementById('user-search-input');
    if (searchInput) {
      if (userSearchState.selectedType === 'Employee') {
        searchInput.placeholder = 'Search for employee by name';
      } else if (userSearchState.selectedType === 'Vendor') {
        searchInput.placeholder = 'Search for vendor by name';
      } else {
        searchInput.placeholder = 'Search for user by name';
      }
    }
  }

  function performSearch(query) {
    userSearchState.currentSearchQuery = query;
    userSearchState.currentOffset = 0;
    userSearchState.hasMore = false;
    showLoading();
    hideError();

    userSearchState.currentRequest = new XMLHttpRequest();
    userSearchState.currentRequest.open('GET', `/user_search/search?q=${encodeURIComponent(query)}&type=${encodeURIComponent(userSearchState.selectedType)}&limit=20&offset=0&project_id=${encodeURIComponent(projectId)}`);
    userSearchState.currentRequest.setRequestHeader('Accept', 'application/json');
    userSearchState.currentRequest.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    userSearchState.currentRequest.onreadystatechange = function() {
      if (this.readyState === XMLHttpRequest.DONE) {
        hideLoading();

        if (this.status === 200) {
          try {
            const response = JSON.parse(this.responseText);
            userSearchState.hasMore = response.has_more || false;
            userSearchState.currentOffset = response.offset + response.total;
            displayResults(response.users || [], false);
          } catch (e) {
            showError('Error parsing search results');
          }
        } else if (this.status === 403) {
          showError('Access denied. You do not have permission to search users.');
        } else if (this.status === 503) {
          showError('User search temporarily unavailable. Please try again later.');
        } else {
          showError('Search failed. Please try again.');
        }

        userSearchState.currentRequest = null;
      }
    };

    userSearchState.currentRequest.onerror = function() {
      hideLoading();
      showError('Network error. Please check your connection.');
      userSearchState.currentRequest = null;
    };

    userSearchState.currentRequest.send();
  }

  function loadMoreResults() {
    if (userSearchState.isLoadingMore || !userSearchState.hasMore || !userSearchState.currentSearchQuery) return;

    userSearchState.isLoadingMore = true;
    showLoadingMore();

    const request = new XMLHttpRequest();
    request.open('GET', `/user_search/search?q=${encodeURIComponent(userSearchState.currentSearchQuery)}&type=${encodeURIComponent(userSearchState.selectedType)}&limit=20&offset=${userSearchState.currentOffset}&project_id=${encodeURIComponent(projectId)}`);
    request.setRequestHeader('Accept', 'application/json');
    request.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    request.onreadystatechange = function() {
      if (this.readyState === XMLHttpRequest.DONE) {
        hideLoadingMore();
        userSearchState.isLoadingMore = false;

        if (this.status === 200) {
          try {
            const response = JSON.parse(this.responseText);
            userSearchState.hasMore = response.has_more || false;
            userSearchState.currentOffset = userSearchState.currentOffset + response.total;
            displayResults(response.users || [], true);
          } catch (e) {
            console.error('Error parsing more results:', e);
          }
        } else {
          console.error('Failed to load more results. Status:', this.status);
        }
      }
    };

    request.onerror = function() {
      hideLoadingMore();
      userSearchState.isLoadingMore = false;
      console.error('Network error loading more results');
    };

    request.send();
  }

  function displayResults(users, append = false) {
    if (!append) {
      resultsList.innerHTML = '';
    }

    // Remove loading indicator if it exists
    const existingLoader = resultsList.querySelector('.loading-more-indicator');
    if (existingLoader) {
      existingLoader.remove();
    }

    if (users.length === 0 && !append) {
      const typeName = userSearchState.selectedType.toLowerCase();
      resultsList.innerHTML = `<li class="no-results">No ${typeName}s found</li>`;
    } else {
      users.forEach(tracked_user => {
        const li = document.createElement('li');
        const statusClass = tracked_user.status === 'Active' ? 'user-status-active' : 'user-status-inactive';

        // Build details based on available information
        let details = `Status: <span class="${statusClass}">${escapeHtml(tracked_user.status || 'N/A')}</span>`;
        if (tracked_user.uid) {
          details += ` | UID: ${escapeHtml(tracked_user.uid)}`;
        }
        if (tracked_user.location) {
          details += ` | Location: ${escapeHtml(tracked_user.location)}`;
        }
        if (tracked_user.user_id) {
          details += ` | ID #: ${escapeHtml(tracked_user.user_id)}`;
        }

        li.innerHTML = `
          <div class="user-name">${highlightMatch(tracked_user.name || 'Unknown', userSearchState.currentSearchQuery)}</div>
          <div class="user-details">${details}</div>
        `;

        li.addEventListener('click', () => {
          selectUser(tracked_user);
        });

        resultsList.appendChild(li);
      });
    }

    showResults();
  }

  function loadFieldMappings() {
    console.log('Starting field mappings load...');
    const request = new XMLHttpRequest();
    request.open('GET', `/user_search/field_mappings?project_id=${encodeURIComponent(projectId)}`);
    request.setRequestHeader('Accept', 'application/json');
    request.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

    request.onreadystatechange = function() {
      console.log('Field mappings request state:', this.readyState, this.status);
      if (this.readyState === XMLHttpRequest.DONE) {
        if (this.status === 200) {
          try {
            console.log('Field mappings response text:', this.responseText);
            const response = JSON.parse(this.responseText);
            userSearchState.fieldMappings = response.field_mappings;
            console.log('Field mappings loaded successfully:', userSearchState.fieldMappings);
            window.bachelpFieldMappings = userSearchState.fieldMappings; // Also set globally for debugging
          } catch (e) {
            console.error('Error parsing field mappings:', e);
          }
        } else {
          console.error('Failed to load field mappings. Status:', this.status, 'Response:', this.responseText);
        }
      }
    };

    request.send();
    console.log('Field mappings request sent');
  }

  function selectUser(user) {
    console.log('Selected user:', user);
    console.log('Current fieldMappings state:', userSearchState.fieldMappings);
    hideResults();
    searchInput.value = user.name || '';

    if (!userSearchState.fieldMappings) {
      console.warn('Field mappings not loaded yet, trying to use global fallback...');
      if (window.bachelpFieldMappings) {
        userSearchState.fieldMappings = window.bachelpFieldMappings;
        console.log('Using global field mappings:', userSearchState.fieldMappings);
      } else {
        console.error('No field mappings available, cannot autofill');
        return;
      }
    }

    populateUserFields(user);
  }

  function populateUserFields(user) {
    // Populate user fields using dynamic mappings
    populateField('user_id_field', user.user_id);
    populateField('user_name_field', user.name);
    populateField('user_email_field', user.email);
    populateField('user_phone_field', user.phone);
    populateField('user_uid_field', user.uid);
    populateField('user_location_field', user.location);

    // Populate User Status dropdown if mapping exists
    if (user.status) {
      populateSelectField('user_status_field', user.status);
    }

    // Populate User Type dropdown if mapping exists
    if (user.user_type) {
      populateSelectField('user_type_field', user.user_type);
    } else {
      // If user_type not provided, use the selected type from the search
      populateSelectField('user_type_field', userSearchState.selectedType);
    }
  }

  function populateField(mappingKey, value) {
    if (!userSearchState.fieldMappings || !userSearchState.fieldMappings[mappingKey]) return;

    const fieldId = userSearchState.fieldMappings[mappingKey];
    const input = document.getElementById(fieldId);

    if (input) {
      input.value = value || '';
      // Trigger change event for any listeners
      input.dispatchEvent(new Event('change', { bubbles: true }));
      input.dispatchEvent(new Event('input', { bubbles: true }));
      console.log(`Populated ${mappingKey} (${fieldId}) with value: ${value || '(blank)'}`);
    } else {
      console.warn(`Could not find input field for ${mappingKey} (${fieldId})`);
    }
  }

  function populateSelectField(mappingKey, value) {
    if (!userSearchState.fieldMappings || !userSearchState.fieldMappings[mappingKey]) return;

    const fieldId = userSearchState.fieldMappings[mappingKey];
    const select = document.getElementById(fieldId);

    if (select && select.tagName === 'SELECT') {
      if (!value) {
        // Clear selection by selecting empty/default option
        select.value = '';
        select.dispatchEvent(new Event('change', { bubbles: true }));
        console.log(`Cleared ${mappingKey} (${fieldId})`);
        return;
      }

      // Try to find matching option by value or text
      const options = select.querySelectorAll('option');
      for (const option of options) {
        if (option.value === value || option.textContent.trim() === value) {
          select.value = option.value;
          select.dispatchEvent(new Event('change', { bubbles: true }));
          console.log(`Populated ${mappingKey} (${fieldId}) with value: ${value}`);
          return;
        }
      }
      console.warn(`Could not find option "${value}" in select field ${mappingKey} (${fieldId})`);
    } else {
      console.warn(`Could not find select field for ${mappingKey} (${fieldId})`);
    }
  }

  function showResults() {
    resultsContainer.style.display = 'block';
  }

  function hideResults() {
    resultsContainer.style.display = 'none';
  }

  function showLoading() {
    loadingIndicator.style.display = 'block';
  }

  function hideLoading() {
    loadingIndicator.style.display = 'none';
  }

  function showError(message) {
    errorContainer.textContent = message;
    errorContainer.style.display = 'block';
  }

  function hideError() {
    errorContainer.style.display = 'none';
  }

  function showLoadingMore() {
    // Remove any existing loading indicator
    const existingLoader = resultsList.querySelector('.loading-more-indicator');
    if (existingLoader) {
      existingLoader.remove();
    }

    const li = document.createElement('li');
    li.className = 'loading-more-indicator';
    li.textContent = 'Loading more results...';
    resultsList.appendChild(li);
  }

  function hideLoadingMore() {
    const loader = resultsList.querySelector('.loading-more-indicator');
    if (loader) {
      loader.remove();
    }
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function highlightMatch(text, query) {
    if (!query || !text) {
      return escapeHtml(text);
    }

    const escapedText = escapeHtml(text);
    const regex = new RegExp(`(${escapeRegex(query)})`, 'gi');
    return escapedText.replace(regex, '<mark class="search-highlight">$1</mark>');
  }

  function escapeRegex(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }
}

function cleanupUserSearch() {
  console.log('Cleaning up user search...');

  // Clear any pending timeout
  if (userSearchState.searchTimeout) {
    clearTimeout(userSearchState.searchTimeout);
    userSearchState.searchTimeout = null;
  }

  // Abort any pending request
  if (userSearchState.currentRequest) {
    userSearchState.currentRequest.abort();
    userSearchState.currentRequest = null;
  }

  // Remove all event listeners
  userSearchState.listeners.forEach(({ element, event, handler }) => {
    element.removeEventListener(event, handler);
  });
  userSearchState.listeners = [];

  console.log('Cleanup complete');
}

// Initialize on DOMContentLoaded
document.addEventListener('DOMContentLoaded', function() {
  console.log('DOMContentLoaded: Initializing user search');
  initializeUserSearch();
});

// Re-initialize when issue form is updated via AJAX (e.g., project change)
// Listen for both jQuery ajaxComplete and native events
if (typeof jQuery !== 'undefined') {
  jQuery(document).on('ajaxComplete', function(event, xhr, settings) {
    // Check if this is an issue form update
    if (settings.url && settings.url.includes('/issues/') && settings.url.includes('/edit')) {
      console.log('AJAX form update detected, re-initializing user search');
      // Small delay to ensure DOM is updated
      setTimeout(function() {
        if (document.getElementById('user-search-widget')) {
          initializeUserSearch();
        }
      }, 100);
    }
  });
}
