/*
 * Copyright (c) 2010, MoPub Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 * * Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 *
 * * Neither the name of 'MoPub Inc.' nor the names of its contributors
 *   may be used to endorse or promote products derived from this software
 *   without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

package com.mopub.mobileads;

import com.mopub.mobileads.util.MoPubUtil;

import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.util.Log;
import android.webkit.WebView;
import android.webkit.WebViewClient;

class AdWebViewClient extends WebViewClient {
	private String 	mClickthroughUrl = "";
	private String 	mRedirectUrl = "";

	public void setClickthroughUrl(String url) {
		mClickthroughUrl = url;
		if (MoPubUtil.DEBUG) Log.d(MoPubUtil.TAG, "clickthrough url: "+mClickthroughUrl);
	}
	
	public void setRedirectUrl(String url) {
		mRedirectUrl = url;
		if (MoPubUtil.DEBUG) Log.d(MoPubUtil.TAG, "redirect url: "+mRedirectUrl);
	}

	@Override
	public boolean shouldOverrideUrlLoading(WebView view, String url) {
		if (MoPubUtil.DEBUG) Log.d(MoPubUtil.TAG, "url: "+url);

		// Check if this is a local call
		if (url.startsWith("mopub://")) {
			if (url.equals("mopub://close")) {
				((AdView)view).pageClosed();
			}
			else if (url.equals("mopub://reload")) {
				((AdView)view).reload();
			}
			return true;
		}

		String uri = url;

		if (mClickthroughUrl != "") {
			uri = mClickthroughUrl + "&r=" + Uri.encode(url);
		}

		if (MoPubUtil.DEBUG) Log.d(MoPubUtil.TAG, "click url: "+uri);


		// and fire off a system wide intent
		view.getContext().startActivity(new Intent(android.content.Intent.ACTION_VIEW, Uri.parse(uri)));
		return true;
	}

	@Override
	public void onPageFinished(WebView view, String url) {
		if (view instanceof AdView) {
			((AdView)view).pageFinished();
		}
	}
	
	@Override
	public void onPageStarted(WebView view, String url, Bitmap favicon) {
		if (!mRedirectUrl.equals("") && url.startsWith(mRedirectUrl)) {
			view.stopLoading();
			view.getContext().startActivity(new Intent(android.content.Intent.ACTION_VIEW, Uri.parse(url)));
		}
	}
}