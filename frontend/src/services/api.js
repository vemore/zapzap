import axios from 'axios';

// Create axios instance with default configuration
export const apiClient = axios.create({
  baseURL: '/api',
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor to add JWT token
apiClient.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

// Response interceptor to handle errors
apiClient.interceptors.response.use(
  (response) => {
    // Pass through successful responses
    return response;
  },
  (error) => {
    // Handle 401 Unauthorized - clear token and redirect to login
    if (error.response && error.response.status === 401) {
      clearAuthToken();
      // Optionally redirect to login page
      // window.location.href = '/login';
    }

    // Handle network errors
    if (error.code === 'ECONNREFUSED' || error.code === 'ECONNABORTED') {
      console.error('Network error:', error.message);
    }

    return Promise.reject(error);
  }
);

// Helper functions for token management
export const setAuthToken = (token) => {
  if (token) {
    localStorage.setItem('token', token);
    apiClient.defaults.headers.common['Authorization'] = `Bearer ${token}`;
  }
};

export const clearAuthToken = () => {
  localStorage.removeItem('token');
  localStorage.removeItem('user');
  delete apiClient.defaults.headers.common['Authorization'];
};

export default apiClient;
