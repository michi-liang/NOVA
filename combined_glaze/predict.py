"""Combine the glaze appearance API with the supplied photo retrieval model."""

import argparse
import json
import math
import os
from pathlib import Path
import re
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

import numpy as np
from PIL import Image, ImageEnhance


DEFAULT_URL = 'https://viewpicture-curriculum-examines-someone.trycloudflare.com/api/glaze/prediction'


class RejectRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def fetch_prediction(top, base, cone):
    url = os.environ.get('GLAZE_API_URL', '').strip() or DEFAULT_URL
    endpoint = urlsplit(url)
    if endpoint.scheme != 'https' or not endpoint.hostname or endpoint.username is not None:
        raise ValueError('GLAZE_API_URL must be an HTTPS URL without embedded credentials.')
    token = (os.environ.get('AI_TEXTURE_TOKEN') or os.environ.get('GLAZE_API_TOKEN') or '').strip()
    if not token or token.startswith('PASTE_'):
        raise ValueError('Set AI_TEXTURE_TOKEN privately before opening NOVA, or load a saved prediction.')
    body = {
        'layers': [{'glaze_id': base, 'order': 1}, {'glaze_id': top, 'order': 2}],
        'cone': cone,
    }
    request = Request(url, data=json.dumps(body).encode(), method='POST', headers={
        'Authorization': f'Bearer {token}', 'Content-Type': 'application/json', 'Accept': 'application/json',
    })
    try:
        with build_opener(RejectRedirects()).open(request, timeout=45) as response:
            return json.load(response)
    except HTTPError as error:
        if error.code in (401, 403):
            raise ValueError('The prediction API denied access. Check your token under Live API access.') from error
        raise ValueError(f'The prediction API returned HTTP {error.code}. Check the endpoint and glaze IDs.') from error
    except URLError as error:
        raise ValueError('Could not reach the prediction API. Check that the service and tunnel are online.') from error


def retrieve_swatch(model_dir, appearance, cone, output):
    """Rank the included samples and adjust the winning photo crop as in the bundle."""
    color = appearance.get('base_color_srgb')
    if not isinstance(color, str) or not re.fullmatch(r'#[0-9A-Fa-f]{6}', color):
        raise ValueError('The appearance prediction must contain a base_color_srgb hex color.')
    contrast = appearance.get('pattern_contrast')
    if contrast is not None and (type(contrast) not in (int, float) or not math.isfinite(contrast)):
        raise ValueError('The appearance prediction has an invalid pattern_contrast.')
    target = np.array([int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)])
    model = json.loads((model_dir / 'model.json').read_text(encoding='utf-8-sig'))
    records = model.get('records')
    if not records:
        raise ValueError('The retrieval model contains no texture records.')

    # The bundled model passes only color, contrast, and cone to retrieval.
    cone_number = cone.removeprefix('Cone ') if isinstance(cone, str) else str(cone or '')

    def distance(record):
        score = 2.4 * float(np.linalg.norm(target - np.array(record['mean_rgb'])))
        weight = 2.4
        sample_contrast = record['appearance'].get('luminance_contrast')
        if contrast is not None and isinstance(sample_contrast, (float, int)):
            score += .7 * abs(contrast - sample_contrast)
            weight += .7
        if cone_number and record.get('cone') and cone_number not in str(record['cone']):
            score += .35
            weight += .35
        return score / weight

    best = min(records, key=distance)
    image_name = best['image']
    if not re.fullmatch(r'sample_\d+\.jpg', image_name):
        raise ValueError('The retrieval model references an invalid sample filename.')
    with Image.open(model_dir / 'textures' / image_name) as source:
        image = source.convert('RGB')
    width, height = image.size
    side = max(48, min(width, height) * 2 // 3)
    left, top = (width - side) // 2, (height - side) // 2
    image = image.crop((left, top, left + side, top + side)).resize((160, 160), Image.Resampling.LANCZOS)
    pixels = np.asarray(image).astype(float) / 255
    shift = np.clip(target - pixels.mean((0, 1)), -.20, .20)
    image = Image.fromarray(np.uint8(np.clip(pixels + shift, 0, 1) * 255))
    image = ImageEnhance.Contrast(image).enhance(1 + max(-.25, min(.25, (contrast or 0) - .45)))
    image.save(output)
    return {
        'base_color_srgb': color.upper(), 'closest_sample': best['pair_label'],
        'source_pdf': best['pdf'], 'source_page': best['page'],
        'distance': round(distance(best), 4), 'candidate_samples': len(records),
    }


def run(model_dir, request_path, report_path):
    request = json.loads(request_path.read_text(encoding='utf-8-sig'))
    saved_path = request.get('prediction_json')
    if saved_path:
        prediction = json.loads(Path(saved_path).read_text(encoding='utf-8-sig'))
        inputs = prediction.get('inputs') or {}
        layers = {layer['order']: layer['glaze_id'] for layer in inputs.get('layers', [])}
        base, top, cone = layers.get(1), layers.get(2), inputs.get('cone')
    else:
        top, base, cone = (request[field].strip() for field in ('top', 'base', 'cone'))
        if not all((top, base, cone)):
            raise ValueError('Enter the top glaze, base glaze, and firing cone.')
        prediction = fetch_prediction(top, base, cone)
    if not isinstance(prediction.get('appearance'), dict):
        raise ValueError('The prediction response does not contain an appearance object.')
    result = retrieve_swatch(model_dir, prediction['appearance'], cone, report_path.with_suffix('.png'))
    result['input_glazes'] = {'top': top, 'base': base, 'cone': cone}
    result['source'] = 'saved_prediction' if saved_path else 'api'
    report_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model_dir', type=Path)
    parser.add_argument('request', type=Path)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    try:
        run(args.model_dir, args.request, args.report)
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        parser.exit(1, f'{error}\n')
