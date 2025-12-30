/* static/admin/js/toggle_vice.js */

document.addEventListener('DOMContentLoaded', function() {
    const $ = django.jQuery;

    function initToggle(row) {
        // 1. 직책(Position) 선택 박스 찾기
        // name 속성이 "-position"으로 끝나는 요소를 찾습니다.
        const $positionSelect = $(row).find('select[name$="-position"]');
        
        // 2. 숨길 대상(담당 강사 선택창) 찾기
        // Django Admin은 필드 이름 앞에 'field-' 클래스를 붙여줍니다.
        const $targetField = $(row).find('.field-managed_teachers');

        if (!$positionSelect.length || !$targetField.length) return;

        function updateVisibility() {
            const val = $positionSelect.val();
            
            // 값이 'VICE'(부원장)일 때만 보여주고, 아니면 숨김
            if (val === 'VICE') {
                $targetField.show(); // 또는 $targetField.slideDown();
            } else {
                $targetField.hide(); // 또는 $targetField.slideUp();
            }
        }

        // 초기 상태 실행
        updateVisibility();

        // 변경될 때마다 실행
        $positionSelect.on('change', updateVisibility);
    }

    // 인라인(Inline) 영역 전체에 대해 스크립트 적용
    $('.inline-group .inline-related').each(function() {
        initToggle(this);
    });
});